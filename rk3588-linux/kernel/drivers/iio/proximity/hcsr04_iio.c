// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * HC-SR04 ultrasonic sensor IIO driver (GPIO triggered / GPIO echo)
 *
 * This driver measures distance by sending a short pulse on the trigger
 * GPIO and timing the pulse width returned on the echo GPIO. The measured
 * distance is exposed through the IIO framework in millimeters.
 */

#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/iio/iio.h>
#include <linux/iio/sysfs.h>
#include <linux/interrupt.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/property.h>

#define HCSR04_DEFAULT_TRIGGER_PULSE_US 10U
#define HCSR04_DEFAULT_STARTUP_TIME_MS  100U
/* 6.45 m max range, one round trip, speed 319 m/s at -20 C */
#define HCSR04_MAX_ECHO_TIME_NS         40438871ULL

struct hcsr04_data {
	struct device *dev;
	struct gpio_desc *gpiod_trig;
	struct gpio_desc *gpiod_echo;
	struct gpio_desc *gpiod_power;
	struct mutex lock;
	struct completion rising;
	struct completion falling;
	ktime_t ts_rising;
	ktime_t ts_falling;
	int irqnr;
	u32 trigger_pulse_us;
	u32 startup_time_ms;
};

static irqreturn_t hcsr04_handle_irq(int irq, void *dev_id)
{
	struct iio_dev *indio_dev = dev_id;
	struct hcsr04_data *data = iio_priv(indio_dev);
	ktime_t now = ktime_get();

	if (gpiod_get_value(data->gpiod_echo)) {
		data->ts_rising = now;
		complete(&data->rising);
	} else {
		data->ts_falling = now;
		complete(&data->falling);
	}

	return IRQ_HANDLED;
}

static int hcsr04_wait_power_ready(struct hcsr04_data *data)
{
	int ret;

	if (!data->gpiod_power)
		return 0;

	ret = pm_runtime_resume_and_get(data->dev);
	if (ret < 0)
		return ret;

	return 0;
}

static void hcsr04_put_power(struct hcsr04_data *data)
{
	if (data->gpiod_power)
		pm_runtime_put_autosuspend(data->dev);
}

static int hcsr04_measure_mm(struct hcsr04_data *data)
{
	int ret;
	ktime_t delta;
	u64 dt_ns;
	u32 distance_mm;

	ret = hcsr04_wait_power_ready(data);
	if (ret < 0)
		return ret;

	mutex_lock(&data->lock);

	reinit_completion(&data->rising);
	reinit_completion(&data->falling);

	/* Emit the trigger pulse required by the HC-SR04. */
	gpiod_set_value(data->gpiod_trig, 1);
	udelay(data->trigger_pulse_us);
	gpiod_set_value(data->gpiod_trig, 0);

	hcsr04_put_power(data);

	ret = wait_for_completion_killable_timeout(&data->rising, HZ / 50);
	if (ret <= 0) {
		mutex_unlock(&data->lock);
		return ret < 0 ? ret : -ETIMEDOUT;
	}

	ret = wait_for_completion_killable_timeout(&data->falling, HZ / 20);
	if (ret <= 0) {
		mutex_unlock(&data->lock);
		return ret < 0 ? ret : -ETIMEDOUT;
	}

	delta = ktime_sub(data->ts_falling, data->ts_rising);
	mutex_unlock(&data->lock);

	dt_ns = ktime_to_ns(delta);
	if (dt_ns > HCSR04_MAX_ECHO_TIME_NS)
		return -EIO;

	/*
	 * Convert echo pulse width to millimeters.
	 * The factor matches the round-trip travel time of sound.
	 */
	distance_mm = div_u64(dt_ns * 106ULL, 617176ULL);

	return distance_mm;
}

static int hcsr04_read_raw(struct iio_dev *indio_dev,
			   const struct iio_chan_spec *chan,
			   int *val, int *val2, long mask)
{
	struct hcsr04_data *data = iio_priv(indio_dev);
	int ret;

	if (chan->type != IIO_DISTANCE)
		return -EINVAL;

	switch (mask) {
	case IIO_CHAN_INFO_RAW:
		ret = hcsr04_measure_mm(data);
		if (ret < 0)
			return ret;
		*val = ret;
		return IIO_VAL_INT;
	case IIO_CHAN_INFO_SCALE:
		*val = 0;
		*val2 = 1000;
		return IIO_VAL_INT_PLUS_MICRO;
	default:
		return -EINVAL;
	}
}

static const struct iio_info hcsr04_iio_info = {
	.read_raw = hcsr04_read_raw,
};

static const struct iio_chan_spec hcsr04_channels[] = {
	{
		.type = IIO_DISTANCE,
		.info_mask_separate = BIT(IIO_CHAN_INFO_RAW) |
				      BIT(IIO_CHAN_INFO_SCALE),
	},
};

static int hcsr04_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct iio_dev *indio_dev;
	struct hcsr04_data *data;
	int ret;

	indio_dev = devm_iio_device_alloc(dev, sizeof(*data));
	if (!indio_dev)
		return -ENOMEM;

	data = iio_priv(indio_dev);
	data->dev = dev;
	data->trigger_pulse_us = HCSR04_DEFAULT_TRIGGER_PULSE_US;
	data->startup_time_ms = HCSR04_DEFAULT_STARTUP_TIME_MS;

	mutex_init(&data->lock);
	init_completion(&data->rising);
	init_completion(&data->falling);

	device_property_read_u32(dev, "trigger-pulse-us",
				 &data->trigger_pulse_us);
	device_property_read_u32(dev, "startup-time-ms",
				 &data->startup_time_ms);

	if (data->trigger_pulse_us == 0 || data->trigger_pulse_us > 1000)
		return dev_err_probe(dev, -EINVAL,
				     "trigger-pulse-us must be in range 1..1000\n");

	data->gpiod_trig = devm_gpiod_get(dev, "trig", GPIOD_OUT_LOW);
	if (IS_ERR(data->gpiod_trig))
		return dev_err_probe(dev, PTR_ERR(data->gpiod_trig),
				     "failed to get trig-gpios\n");

	data->gpiod_echo = devm_gpiod_get(dev, "echo", GPIOD_IN);
	if (IS_ERR(data->gpiod_echo))
		return dev_err_probe(dev, PTR_ERR(data->gpiod_echo),
				     "failed to get echo-gpios\n");

	data->gpiod_power = devm_gpiod_get_optional(dev, "power", GPIOD_OUT_LOW);
	if (IS_ERR(data->gpiod_power))
		return dev_err_probe(dev, PTR_ERR(data->gpiod_power),
				     "failed to get power-gpios\n");

	if (gpiod_cansleep(data->gpiod_trig) || gpiod_cansleep(data->gpiod_echo))
		return dev_err_probe(dev, -ENODEV,
				     "cansleep GPIOs are not supported\n");

	data->irqnr = gpiod_to_irq(data->gpiod_echo);
	if (data->irqnr < 0)
		return dev_err_probe(dev, data->irqnr, "gpiod_to_irq failed\n");

	ret = devm_request_irq(dev, data->irqnr, hcsr04_handle_irq,
			       IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,
			       dev_name(dev), indio_dev);
	if (ret)
		return dev_err_probe(dev, ret, "request_irq failed\n");

	indio_dev->name = "hcsr04";
	indio_dev->info = &hcsr04_iio_info;
	indio_dev->modes = INDIO_DIRECT_MODE;
	indio_dev->channels = hcsr04_channels;
	indio_dev->num_channels = ARRAY_SIZE(hcsr04_channels);

	platform_set_drvdata(pdev, indio_dev);

	ret = iio_device_register(indio_dev);
	if (ret)
		return dev_err_probe(dev, ret, "iio_device_register failed\n");

	if (data->gpiod_power) {
		pm_runtime_set_autosuspend_delay(dev, 1000);
		pm_runtime_use_autosuspend(dev);

		ret = pm_runtime_set_active(dev);
		if (ret) {
			dev_err(dev, "pm_runtime_set_active failed: %d\n", ret);
			iio_device_unregister(indio_dev);
			return ret;
		}

		pm_runtime_enable(dev);
		pm_runtime_idle(dev);
	}

	dev_info(dev, "HC-SR04 IIO sensor registered (trigger pulse %u us)\n",
		 data->trigger_pulse_us);

	return 0;
}

static int hcsr04_remove(struct platform_device *pdev)
{
	struct iio_dev *indio_dev = platform_get_drvdata(pdev);
	struct hcsr04_data *data = iio_priv(indio_dev);

	iio_device_unregister(indio_dev);

	if (data->gpiod_power) {
		pm_runtime_disable(data->dev);
		pm_runtime_set_suspended(data->dev);
	}

	return 0;
}

static int hcsr04_runtime_suspend(struct device *dev)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct iio_dev *indio_dev = platform_get_drvdata(pdev);
	struct hcsr04_data *data = iio_priv(indio_dev);

	if (!data->gpiod_power)
		return 0;

	gpiod_set_value(data->gpiod_power, 0);
	return 0;
}

static int hcsr04_runtime_resume(struct device *dev)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct iio_dev *indio_dev = platform_get_drvdata(pdev);
	struct hcsr04_data *data = iio_priv(indio_dev);

	if (!data->gpiod_power)
		return 0;

	gpiod_set_value(data->gpiod_power, 1);
	msleep(data->startup_time_ms);
	return 0;
}

static const struct dev_pm_ops hcsr04_pm_ops = {
	SET_RUNTIME_PM_OPS(hcsr04_runtime_suspend, hcsr04_runtime_resume, NULL)
};

static const struct of_device_id hcsr04_of_match[] = {
	{ .compatible = "qwe036,hc-sr04" },
	{ }
};
MODULE_DEVICE_TABLE(of, hcsr04_of_match);

static struct platform_driver hcsr04_driver = {
	.probe = hcsr04_probe,
	.remove = hcsr04_remove,
	.driver = {
		.name = "hcsr04-gpio",
		.of_match_table = hcsr04_of_match,
		.pm = &hcsr04_pm_ops,
	},
};
module_platform_driver(hcsr04_driver);

MODULE_AUTHOR("OpenAI");
MODULE_DESCRIPTION("HC-SR04 ultrasonic distance sensor IIO driver");
MODULE_LICENSE("GPL");
