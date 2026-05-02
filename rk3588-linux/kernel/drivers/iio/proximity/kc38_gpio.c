// SPDX-License-Identifier: GPL-2.0-only
/*
 * KC38 infrared proximity sensor driver
 *
 * The KC38 module exposes a single digital output:
 *   high: object detected
 *   low : no object detected
 *
 * This driver keeps CPU usage low by latching state changes from a GPIO IRQ
 * instead of polling. The current state is exposed as an IIO proximity value.
 */

#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/iio/events.h>
#include <linux/iio/iio.h>
#include <linux/interrupt.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>

struct kc38_data {
	struct device *dev;
	struct gpio_desc *gpiod_out;
	struct mutex lock;
	bool state;
	bool state_valid;
	bool event_en_rising;
	bool event_en_falling;
};

static irqreturn_t kc38_irq_thread(int irq, void *private)
{
	struct iio_dev *indio_dev = private;
	struct kc38_data *data = iio_priv(indio_dev);
	bool new_state;
	bool old_state;
	bool old_valid;
	bool push_event = false;
	enum iio_event_direction dir = IIO_EV_DIR_EITHER;
	s64 timestamp = iio_get_time_ns(indio_dev);

	new_state = gpiod_get_value(data->gpiod_out);

	mutex_lock(&data->lock);

	old_state = data->state;
	old_valid = data->state_valid;

	data->state = new_state;
	data->state_valid = true;

	/*
	 * Push an event only when the state actually changes. This keeps user
	 * space event consumers aligned with the sensor's digital transitions.
	 */
	if (!old_valid || old_state != new_state) {
		if (new_state && data->event_en_rising) {
			push_event = true;
			dir = IIO_EV_DIR_RISING;
		} else if (!new_state && data->event_en_falling) {
			push_event = true;
			dir = IIO_EV_DIR_FALLING;
		}
	}

	mutex_unlock(&data->lock);

	if (push_event)
		iio_push_event(indio_dev,
			       IIO_UNMOD_EVENT_CODE(IIO_PROXIMITY, 0,
						    IIO_EV_TYPE_THRESH, dir),
			       timestamp);

	return IRQ_HANDLED;
}

static int kc38_read_raw(struct iio_dev *indio_dev,
			 const struct iio_chan_spec *chan,
			 int *val, int *val2, long mask)
{
	struct kc38_data *data = iio_priv(indio_dev);
	int ret;

	if (chan->type != IIO_PROXIMITY)
		return -EINVAL;

	switch (mask) {
	case IIO_CHAN_INFO_RAW:
		mutex_lock(&data->lock);
		if (!data->state_valid) {
			ret = gpiod_get_value(data->gpiod_out);
			if (ret < 0) {
				mutex_unlock(&data->lock);
				return ret;
			}

			data->state = !!ret;
			data->state_valid = true;
		}

		*val = data->state ? 1 : 0;
		mutex_unlock(&data->lock);
		return IIO_VAL_INT;
	case IIO_CHAN_INFO_SCALE:
		/*
		 * The module is binary: 1 means obstacle detected, 0 means clear.
		 */
		*val = 1;
		*val2 = 0;
		return IIO_VAL_INT;
	default:
		return -EINVAL;
	}
}

static int kc38_read_event_config(struct iio_dev *indio_dev,
				  const struct iio_chan_spec *chan,
				  enum iio_event_type type,
				  enum iio_event_direction dir)
{
	struct kc38_data *data = iio_priv(indio_dev);
	int ret;

	if (chan->type != IIO_PROXIMITY || type != IIO_EV_TYPE_THRESH)
		return -EINVAL;

	mutex_lock(&data->lock);
	switch (dir) {
	case IIO_EV_DIR_RISING:
		ret = data->event_en_rising;
		break;
	case IIO_EV_DIR_FALLING:
		ret = data->event_en_falling;
		break;
	default:
		ret = -EINVAL;
		break;
	}
	mutex_unlock(&data->lock);

	return ret;
}

static int kc38_write_event_config(struct iio_dev *indio_dev,
				   const struct iio_chan_spec *chan,
				   enum iio_event_type type,
				   enum iio_event_direction dir, int state)
{
	struct kc38_data *data = iio_priv(indio_dev);

	if (chan->type != IIO_PROXIMITY || type != IIO_EV_TYPE_THRESH)
		return -EINVAL;

	mutex_lock(&data->lock);
	switch (dir) {
	case IIO_EV_DIR_RISING:
		data->event_en_rising = !!state;
		break;
	case IIO_EV_DIR_FALLING:
		data->event_en_falling = !!state;
		break;
	default:
		mutex_unlock(&data->lock);
		return -EINVAL;
	}
	mutex_unlock(&data->lock);

	return 0;
}

static const struct iio_event_spec kc38_event_spec[] = {
	{
		.type = IIO_EV_TYPE_THRESH,
		.dir = IIO_EV_DIR_RISING,
		.mask_separate = BIT(IIO_EV_INFO_ENABLE),
	},
	{
		.type = IIO_EV_TYPE_THRESH,
		.dir = IIO_EV_DIR_FALLING,
		.mask_separate = BIT(IIO_EV_INFO_ENABLE),
	},
};

static const struct iio_chan_spec kc38_channels[] = {
	{
		.type = IIO_PROXIMITY,
		.info_mask_separate = BIT(IIO_CHAN_INFO_RAW) |
				      BIT(IIO_CHAN_INFO_SCALE),
		.event_spec = kc38_event_spec,
		.num_event_specs = ARRAY_SIZE(kc38_event_spec),
	},
};

static const struct iio_info kc38_iio_info = {
	.read_raw = kc38_read_raw,
	.read_event_config = kc38_read_event_config,
	.write_event_config = kc38_write_event_config,
};

static int kc38_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct iio_dev *indio_dev;
	struct kc38_data *data;
	int irq;
	int ret;

	indio_dev = devm_iio_device_alloc(dev, sizeof(*data));
	if (!indio_dev)
		return -ENOMEM;

	data = iio_priv(indio_dev);
	data->dev = dev;
	mutex_init(&data->lock);

	data->gpiod_out = devm_gpiod_get(dev, "out", GPIOD_IN);
	if (IS_ERR(data->gpiod_out))
		return dev_err_probe(dev, PTR_ERR(data->gpiod_out),
				     "failed to get out-gpios\n");

	if (gpiod_cansleep(data->gpiod_out))
		return dev_err_probe(dev, -ENODEV,
				     "cansleep GPIOs are not supported\n");

	ret = gpiod_get_value(data->gpiod_out);
	if (ret < 0)
		return dev_err_probe(dev, ret, "failed to read initial GPIO state\n");

	data->state = !!ret;
	data->state_valid = true;

	irq = gpiod_to_irq(data->gpiod_out);
	if (irq < 0)
		return dev_err_probe(dev, irq, "gpiod_to_irq failed\n");

	ret = devm_request_threaded_irq(dev, irq, NULL, kc38_irq_thread,
					IRQF_ONESHOT |
					IRQF_TRIGGER_RISING |
					IRQF_TRIGGER_FALLING,
					dev_name(dev), indio_dev);
	if (ret)
		return dev_err_probe(dev, ret, "request irq failed\n");

	indio_dev->name = "kc38";
	indio_dev->modes = INDIO_DIRECT_MODE;
	indio_dev->info = &kc38_iio_info;
	indio_dev->channels = kc38_channels;
	indio_dev->num_channels = ARRAY_SIZE(kc38_channels);

	platform_set_drvdata(pdev, indio_dev);

	ret = devm_iio_device_register(dev, indio_dev);
	if (ret)
		return dev_err_probe(dev, ret, "failed to register IIO device\n");

	dev_info(dev, "KC38 infrared proximity sensor registered\n");

	return 0;
}

static const struct of_device_id kc38_of_match[] = {
	{ .compatible = "qwe036,kc38-ir" },
	{ }
};
MODULE_DEVICE_TABLE(of, kc38_of_match);

static struct platform_driver kc38_driver = {
	.probe = kc38_probe,
	.driver = {
		.name = "kc38-gpio",
		.of_match_table = kc38_of_match,
	},
};
module_platform_driver(kc38_driver);

MODULE_AUTHOR("OpenAI");
MODULE_DESCRIPTION("KC38 GPIO infrared proximity sensor driver");
MODULE_LICENSE("GPL");
