// SPDX-License-Identifier: GPL-2.0
/*
 * BMI270 - Bosch IMU core
 *
 * This backport keeps the 5.10 integration small and predictable:
 * - based on the upstream Linux BMI270 register model
 * - uses Bosch's published BMI270 configuration blob
 * - exposes accelerometer, gyroscope and temperature through IIO
 *
 * Triggered buffers, motion events and step counter support can be added
 * later if this board wiring also provides an interrupt line.
 */
#include <linux/bitfield.h>
#include <linux/delay.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/regmap.h>

#include <linux/iio/iio.h>
#include <linux/iio/sysfs.h>

#include "bmi270.h"
#include "bmi270_init_data.h"

#define BMI270_REG_CHIP_ID			0x00
#define BMI270_CHIP_ID_VAL			0x24
#define BMI160_CHIP_ID_VAL			0xD1

#define BMI270_REG_INTERNAL_STATUS		0x21
#define BMI270_INTERNAL_STATUS_MSG_MSK		GENMASK(3, 0)
#define BMI270_INTERNAL_STATUS_INIT_OK		0x01
#define BMI270_INTERNAL_STATUS_AXES_REMAP_ERR	BIT(5)
#define BMI270_INTERNAL_STATUS_ODR_50HZ_ERR	BIT(6)

#define BMI270_REG_TEMP_0			0x22

#define BMI270_REG_ACC_CONF			0x40
#define BMI270_ACC_CONF_ODR_MSK		GENMASK(3, 0)
#define BMI270_ACC_CONF_BWP_MSK		GENMASK(6, 4)
#define BMI270_ACC_CONF_ODR_100HZ		0x08
#define BMI270_ACC_CONF_BWP_NORMAL		0x02

#define BMI270_REG_ACC_RANGE			0x41
#define BMI270_ACC_RANGE_MSK			GENMASK(1, 0)

#define BMI270_REG_GYR_CONF			0x42
#define BMI270_GYR_CONF_ODR_MSK		GENMASK(3, 0)
#define BMI270_GYR_CONF_BWP_MSK		GENMASK(5, 4)
#define BMI270_GYR_CONF_ODR_200HZ		0x09
#define BMI270_GYR_CONF_BWP_NORMAL		0x02

#define BMI270_REG_GYR_RANGE			0x43
#define BMI270_GYR_RANGE_MSK			GENMASK(2, 0)

#define BMI270_REG_INIT_CTRL			0x59
#define BMI270_INIT_CTRL_LOAD_DONE_MSK		BIT(0)
#define BMI270_REG_INIT_DATA			0x5e

#define BMI270_REG_PWR_CONF			0x7c
#define BMI270_PWR_CONF_ADV_PWR_SAVE_MSK	BIT(0)
#define BMI270_PWR_CONF_FIFO_WKUP_MSK		BIT(1)
#define BMI270_PWR_CONF_FUP_EN_MSK		BIT(2)

#define BMI270_REG_PWR_CTRL			0x7d
#define BMI270_PWR_CTRL_AUX_EN_MSK		BIT(0)
#define BMI270_PWR_CTRL_GYR_EN_MSK		BIT(1)
#define BMI270_PWR_CTRL_ACC_EN_MSK		BIT(2)
#define BMI270_PWR_CTRL_TEMP_EN_MSK		BIT(3)

#define BMI270_REG_ACC_X_L			0x0c
#define BMI270_REG_GYR_X_L			0x12

#define BMI270_TEMP_OFFSET			11776
#define BMI270_TEMP_SCALE			1953125

enum bmi270_scan {
	BMI270_SCAN_ACCEL_X,
	BMI270_SCAN_ACCEL_Y,
	BMI270_SCAN_ACCEL_Z,
	BMI270_SCAN_GYRO_X,
	BMI270_SCAN_GYRO_Y,
	BMI270_SCAN_GYRO_Z,
	BMI270_SCAN_TEMP,
};

enum bmi270_sensor_type {
	BMI270_ACCEL = 0,
	BMI270_GYRO,
	BMI270_TEMP,
};

struct bmi270_scale {
	int scale;
	int uscale;
};

struct bmi270_odr {
	int odr;
	int uodr;
};

struct bmi270_scale_item {
	const struct bmi270_scale *tbl;
	int num;
};

struct bmi270_odr_item {
	const struct bmi270_odr *tbl;
	const u8 *vals;
	int num;
};

static const struct bmi270_scale bmi270_accel_scale[] = {
	{ 0, 598 },
	{ 0, 1197 },
	{ 0, 2394 },
	{ 0, 4788 },
};

static const struct bmi270_scale bmi270_gyro_scale[] = {
	{ 0, 1065 },
	{ 0, 532 },
	{ 0, 266 },
	{ 0, 133 },
	{ 0, 66 },
};

static const struct bmi270_scale bmi270_temp_scale[] = {
	{ BMI270_TEMP_SCALE / 1000000, BMI270_TEMP_SCALE % 1000000 },
};

static const struct bmi270_scale_item bmi270_scale_table[] = {
	[BMI270_ACCEL] = {
		.tbl = bmi270_accel_scale,
		.num = ARRAY_SIZE(bmi270_accel_scale),
	},
	[BMI270_GYRO] = {
		.tbl = bmi270_gyro_scale,
		.num = ARRAY_SIZE(bmi270_gyro_scale),
	},
	[BMI270_TEMP] = {
		.tbl = bmi270_temp_scale,
		.num = ARRAY_SIZE(bmi270_temp_scale),
	},
};

static const struct bmi270_odr bmi270_accel_odr[] = {
	{ 0, 781250 }, { 1, 562500 }, { 3, 125000 }, { 6, 250000 },
	{ 12, 500000 }, { 25, 0 }, { 50, 0 }, { 100, 0 },
	{ 200, 0 }, { 400, 0 }, { 800, 0 }, { 1600, 0 },
};

static const u8 bmi270_accel_odr_vals[] = {
	0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
	0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
};

static const struct bmi270_odr bmi270_gyro_odr[] = {
	{ 25, 0 }, { 50, 0 }, { 100, 0 }, { 200, 0 },
	{ 400, 0 }, { 800, 0 }, { 1600, 0 }, { 3200, 0 },
};

static const u8 bmi270_gyro_odr_vals[] = {
	0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d,
};

static const struct bmi270_odr_item bmi270_odr_table[] = {
	[BMI270_ACCEL] = {
		.tbl = bmi270_accel_odr,
		.vals = bmi270_accel_odr_vals,
		.num = ARRAY_SIZE(bmi270_accel_odr),
	},
	[BMI270_GYRO] = {
		.tbl = bmi270_gyro_odr,
		.vals = bmi270_gyro_odr_vals,
		.num = ARRAY_SIZE(bmi270_gyro_odr),
	},
};

static const struct iio_mount_matrix *
bmi270_get_mount_matrix(const struct iio_dev *indio_dev,
			const struct iio_chan_spec *chan)
{
	struct bmi270_data *data = iio_priv(indio_dev);

	return &data->orientation;
}

static const struct iio_chan_spec_ext_info bmi270_ext_info[] = {
	IIO_MOUNT_MATRIX(IIO_SHARED_BY_DIR, bmi270_get_mount_matrix),
	{ }
};

#define BMI270_ACCEL_CHANNEL(_axis, _index) {				\
	.type = IIO_ACCEL,						\
	.modified = 1,							\
	.channel2 = IIO_MOD_##_axis,					\
	.info_mask_separate = BIT(IIO_CHAN_INFO_RAW),			\
	.info_mask_shared_by_type = BIT(IIO_CHAN_INFO_SCALE) |		\
		BIT(IIO_CHAN_INFO_SAMP_FREQ),				\
	.info_mask_shared_by_type_available = BIT(IIO_CHAN_INFO_SCALE) |	\
		BIT(IIO_CHAN_INFO_SAMP_FREQ),				\
	.ext_info = bmi270_ext_info,					\
	.scan_index = _index,						\
	.scan_type = { .sign = 's', .realbits = 16, .storagebits = 16,	\
		       .endianness = IIO_LE, },				\
}

#define BMI270_GYRO_CHANNEL(_axis, _index) {				\
	.type = IIO_ANGL_VEL,						\
	.modified = 1,							\
	.channel2 = IIO_MOD_##_axis,					\
	.info_mask_separate = BIT(IIO_CHAN_INFO_RAW),			\
	.info_mask_shared_by_type = BIT(IIO_CHAN_INFO_SCALE) |		\
		BIT(IIO_CHAN_INFO_SAMP_FREQ),				\
	.info_mask_shared_by_type_available = BIT(IIO_CHAN_INFO_SCALE) |	\
		BIT(IIO_CHAN_INFO_SAMP_FREQ),				\
	.ext_info = bmi270_ext_info,					\
	.scan_index = _index,						\
	.scan_type = { .sign = 's', .realbits = 16, .storagebits = 16,	\
		       .endianness = IIO_LE, },				\
}

static const struct iio_chan_spec bmi270_channels[] = {
	BMI270_ACCEL_CHANNEL(X, BMI270_SCAN_ACCEL_X),
	BMI270_ACCEL_CHANNEL(Y, BMI270_SCAN_ACCEL_Y),
	BMI270_ACCEL_CHANNEL(Z, BMI270_SCAN_ACCEL_Z),
	BMI270_GYRO_CHANNEL(X, BMI270_SCAN_GYRO_X),
	BMI270_GYRO_CHANNEL(Y, BMI270_SCAN_GYRO_Y),
	BMI270_GYRO_CHANNEL(Z, BMI270_SCAN_GYRO_Z),
	{
		.type = IIO_TEMP,
		.info_mask_separate = BIT(IIO_CHAN_INFO_RAW) |
				      BIT(IIO_CHAN_INFO_SCALE) |
				      BIT(IIO_CHAN_INFO_OFFSET),
		.scan_index = -1,
	},
};

static int bmi270_validate_chip_id(struct bmi270_data *data)
{
	unsigned int chip_id;
	int ret;
	struct device *dev = regmap_get_device(data->regmap);

	ret = regmap_read(data->regmap, BMI270_REG_CHIP_ID, &chip_id);
	if (ret)
		return ret;

	if (chip_id == BMI160_CHIP_ID_VAL) {
		dev_err(dev, "chip id 0x%02x looks like BMI160, not BMI270\n",
			chip_id);
		return -ENODEV;
	}

	if (chip_id != BMI270_CHIP_ID_VAL) {
		dev_err(dev, "unexpected chip id 0x%02x, expected 0x%02x\n",
			chip_id, BMI270_CHIP_ID_VAL);
		return -ENODEV;
	}

	return 0;
}

static int bmi270_load_config(struct bmi270_data *data)
{
	unsigned int status;
	int ret;
	struct device *dev = regmap_get_device(data->regmap);

	/*
	 * The BMI270 boots with advanced power save enabled, which blocks
	 * access to the init-data upload path. The datasheet requires a short
	 * wait after clearing that bit before the config window becomes valid.
	 */
	ret = regmap_update_bits(data->regmap, BMI270_REG_PWR_CONF,
				 BMI270_PWR_CONF_ADV_PWR_SAVE_MSK, 0);
	if (ret)
		return ret;

	usleep_range(450, 1000);

	ret = regmap_update_bits(data->regmap, BMI270_REG_INIT_CTRL,
				 BMI270_INIT_CTRL_LOAD_DONE_MSK, 0);
	if (ret)
		return ret;

	ret = regmap_bulk_write(data->regmap, BMI270_REG_INIT_DATA,
				bmi270_init_data, BMI270_INIT_DATA_LEN);
	if (ret)
		return ret;

	ret = regmap_update_bits(data->regmap, BMI270_REG_INIT_CTRL,
				 BMI270_INIT_CTRL_LOAD_DONE_MSK,
				 BMI270_INIT_CTRL_LOAD_DONE_MSK);
	if (ret)
		return ret;

	usleep_range(140000, 160000);

	ret = regmap_read(data->regmap, BMI270_REG_INTERNAL_STATUS, &status);
	if (ret)
		return ret;

	if (FIELD_GET(BMI270_INTERNAL_STATUS_MSG_MSK, status) !=
	    BMI270_INTERNAL_STATUS_INIT_OK) {
		dev_err(dev, "init status 0x%02x: device did not enter INIT_OK\n",
			status);
		return -ENODEV;
	}

	if (status & (BMI270_INTERNAL_STATUS_AXES_REMAP_ERR |
		      BMI270_INTERNAL_STATUS_ODR_50HZ_ERR)) {
		dev_err(dev, "init status 0x%02x reports configuration error\n",
			status);
		return -EINVAL;
	}

	return 0;
}

static int bmi270_chip_init(struct bmi270_data *data)
{
	int ret;
	unsigned int mask;
	unsigned int val;

	ret = bmi270_validate_chip_id(data);
	if (ret)
		return ret;

	ret = bmi270_load_config(data);
	if (ret)
		return ret;

	mask = BMI270_PWR_CTRL_AUX_EN_MSK | BMI270_PWR_CTRL_GYR_EN_MSK |
	       BMI270_PWR_CTRL_ACC_EN_MSK | BMI270_PWR_CTRL_TEMP_EN_MSK;
	ret = regmap_update_bits(data->regmap, BMI270_REG_PWR_CTRL, mask, mask);
	if (ret)
		return ret;

	mask = BMI270_ACC_CONF_ODR_MSK | BMI270_ACC_CONF_BWP_MSK;
	val = FIELD_PREP(BMI270_ACC_CONF_ODR_MSK, BMI270_ACC_CONF_ODR_100HZ) |
	      FIELD_PREP(BMI270_ACC_CONF_BWP_MSK, BMI270_ACC_CONF_BWP_NORMAL);
	ret = regmap_update_bits(data->regmap, BMI270_REG_ACC_CONF, mask, val);
	if (ret)
		return ret;

	mask = BMI270_GYR_CONF_ODR_MSK | BMI270_GYR_CONF_BWP_MSK;
	val = FIELD_PREP(BMI270_GYR_CONF_ODR_MSK, BMI270_GYR_CONF_ODR_200HZ) |
	      FIELD_PREP(BMI270_GYR_CONF_BWP_MSK, BMI270_GYR_CONF_BWP_NORMAL);
	ret = regmap_update_bits(data->regmap, BMI270_REG_GYR_CONF, mask, val);
	if (ret)
		return ret;

	/*
	 * Mirror the upstream default here: keep FIFO wake-up enabled while
	 * leaving advanced power save and feature-page auto-update disabled.
	 */
	return regmap_write(data->regmap, BMI270_REG_PWR_CONF,
			    BMI270_PWR_CONF_FIFO_WKUP_MSK);
}

static int bmi270_get_data(struct bmi270_data *data, int chan_type, int axis,
			   int *val)
{
	__le16 sample;
	unsigned int reg;
	int ret;

	switch (chan_type) {
	case IIO_ACCEL:
		reg = BMI270_REG_ACC_X_L + (axis - IIO_MOD_X) * 2;
		break;
	case IIO_ANGL_VEL:
		reg = BMI270_REG_GYR_X_L + (axis - IIO_MOD_X) * 2;
		break;
	case IIO_TEMP:
		reg = BMI270_REG_TEMP_0;
		break;
	default:
		return -EINVAL;
	}

	mutex_lock(&data->mutex);
	ret = regmap_bulk_read(data->regmap, reg, &sample, sizeof(sample));
	mutex_unlock(&data->mutex);
	if (ret)
		return ret;

	*val = sign_extend32(le16_to_cpu(sample), 15);

	return IIO_VAL_INT;
}

static int bmi270_set_scale(struct bmi270_data *data, int chan_type, int uscale)
{
	const struct bmi270_scale_item *item;
	unsigned int reg;
	unsigned int mask;
	int i, ret = -EINVAL;

	switch (chan_type) {
	case IIO_ACCEL:
		reg = BMI270_REG_ACC_RANGE;
		mask = BMI270_ACC_RANGE_MSK;
		item = &bmi270_scale_table[BMI270_ACCEL];
		break;
	case IIO_ANGL_VEL:
		reg = BMI270_REG_GYR_RANGE;
		mask = BMI270_GYR_RANGE_MSK;
		item = &bmi270_scale_table[BMI270_GYRO];
		break;
	default:
		return -EINVAL;
	}

	mutex_lock(&data->mutex);
	for (i = 0; i < item->num; i++) {
		if (item->tbl[i].uscale != uscale)
			continue;

		ret = regmap_update_bits(data->regmap, reg, mask, i);
		break;
	}
	mutex_unlock(&data->mutex);

	return ret;
}

static int bmi270_get_scale(struct bmi270_data *data, int chan_type, int *scale,
			    int *uscale)
{
	const struct bmi270_scale_item *item;
	unsigned int val = 0;
	int ret = 0;

	switch (chan_type) {
	case IIO_ACCEL:
		item = &bmi270_scale_table[BMI270_ACCEL];
		ret = regmap_read(data->regmap, BMI270_REG_ACC_RANGE, &val);
		if (ret)
			return ret;
		val = FIELD_GET(BMI270_ACC_RANGE_MSK, val);
		break;
	case IIO_ANGL_VEL:
		item = &bmi270_scale_table[BMI270_GYRO];
		ret = regmap_read(data->regmap, BMI270_REG_GYR_RANGE, &val);
		if (ret)
			return ret;
		val = FIELD_GET(BMI270_GYR_RANGE_MSK, val);
		break;
	case IIO_TEMP:
		item = &bmi270_scale_table[BMI270_TEMP];
		val = 0;
		break;
	default:
		return -EINVAL;
	}

	if (val >= item->num)
		return -EINVAL;

	*scale = item->tbl[val].scale;
	*uscale = item->tbl[val].uscale;

	return 0;
}

static int bmi270_set_odr(struct bmi270_data *data, int chan_type, int odr,
			  int uodr)
{
	const struct bmi270_odr_item *item;
	unsigned int reg;
	unsigned int mask;
	int i, ret = -EINVAL;

	switch (chan_type) {
	case IIO_ACCEL:
		item = &bmi270_odr_table[BMI270_ACCEL];
		reg = BMI270_REG_ACC_CONF;
		mask = BMI270_ACC_CONF_ODR_MSK;
		break;
	case IIO_ANGL_VEL:
		item = &bmi270_odr_table[BMI270_GYRO];
		reg = BMI270_REG_GYR_CONF;
		mask = BMI270_GYR_CONF_ODR_MSK;
		break;
	default:
		return -EINVAL;
	}

	mutex_lock(&data->mutex);
	for (i = 0; i < item->num; i++) {
		if (item->tbl[i].odr != odr || item->tbl[i].uodr != uodr)
			continue;

		ret = regmap_update_bits(data->regmap, reg, mask, item->vals[i]);
		break;
	}
	mutex_unlock(&data->mutex);

	return ret;
}

static int bmi270_get_odr(struct bmi270_data *data, int chan_type, int *odr,
			  int *uodr)
{
	const struct bmi270_odr_item *item;
	unsigned int val;
	int i, ret;

	mutex_lock(&data->mutex);
	switch (chan_type) {
	case IIO_ACCEL:
		item = &bmi270_odr_table[BMI270_ACCEL];
		ret = regmap_read(data->regmap, BMI270_REG_ACC_CONF, &val);
		if (!ret)
			val = FIELD_GET(BMI270_ACC_CONF_ODR_MSK, val);
		break;
	case IIO_ANGL_VEL:
		item = &bmi270_odr_table[BMI270_GYRO];
		ret = regmap_read(data->regmap, BMI270_REG_GYR_CONF, &val);
		if (!ret)
			val = FIELD_GET(BMI270_GYR_CONF_ODR_MSK, val);
		break;
	default:
		mutex_unlock(&data->mutex);
		return -EINVAL;
	}
	mutex_unlock(&data->mutex);
	if (ret)
		return ret;

	for (i = 0; i < item->num; i++) {
		if (item->vals[i] != val)
			continue;

		*odr = item->tbl[i].odr;
		*uodr = item->tbl[i].uodr;
		return 0;
	}

	return -EINVAL;
}

static int bmi270_read_raw(struct iio_dev *indio_dev,
			   struct iio_chan_spec const *chan,
			   int *val, int *val2, long mask)
{
	struct bmi270_data *data = iio_priv(indio_dev);
	int ret;

	switch (mask) {
	case IIO_CHAN_INFO_RAW:
		return bmi270_get_data(data, chan->type, chan->channel2, val);
	case IIO_CHAN_INFO_SCALE:
		ret = bmi270_get_scale(data, chan->type, val, val2);
		return ret ? ret : IIO_VAL_INT_PLUS_MICRO;
	case IIO_CHAN_INFO_OFFSET:
		if (chan->type != IIO_TEMP)
			return -EINVAL;
		*val = BMI270_TEMP_OFFSET;
		return IIO_VAL_INT;
	case IIO_CHAN_INFO_SAMP_FREQ:
		ret = bmi270_get_odr(data, chan->type, val, val2);
		return ret ? ret : IIO_VAL_INT_PLUS_MICRO;
	default:
		return -EINVAL;
	}
}

static int bmi270_write_raw(struct iio_dev *indio_dev,
			    struct iio_chan_spec const *chan,
			    int val, int val2, long mask)
{
	struct bmi270_data *data = iio_priv(indio_dev);

	switch (mask) {
	case IIO_CHAN_INFO_SCALE:
		return bmi270_set_scale(data, chan->type, val2);
	case IIO_CHAN_INFO_SAMP_FREQ:
		return bmi270_set_odr(data, chan->type, val, val2);
	default:
		return -EINVAL;
	}
}

static int bmi270_read_avail(struct iio_dev *indio_dev,
			     struct iio_chan_spec const *chan,
			     const int **vals, int *type, int *length,
			     long mask)
{
	switch (mask) {
	case IIO_CHAN_INFO_SCALE:
		*type = IIO_VAL_INT_PLUS_MICRO;
		switch (chan->type) {
		case IIO_ACCEL:
			*vals = (const int *)bmi270_accel_scale;
			*length = ARRAY_SIZE(bmi270_accel_scale) * 2;
			return IIO_AVAIL_LIST;
		case IIO_ANGL_VEL:
			*vals = (const int *)bmi270_gyro_scale;
			*length = ARRAY_SIZE(bmi270_gyro_scale) * 2;
			return IIO_AVAIL_LIST;
		default:
			return -EINVAL;
		}
	case IIO_CHAN_INFO_SAMP_FREQ:
		*type = IIO_VAL_INT_PLUS_MICRO;
		switch (chan->type) {
		case IIO_ACCEL:
			*vals = (const int *)bmi270_accel_odr;
			*length = ARRAY_SIZE(bmi270_accel_odr) * 2;
			return IIO_AVAIL_LIST;
		case IIO_ANGL_VEL:
			*vals = (const int *)bmi270_gyro_odr;
			*length = ARRAY_SIZE(bmi270_gyro_odr) * 2;
			return IIO_AVAIL_LIST;
		default:
			return -EINVAL;
		}
	default:
		return -EINVAL;
	}
}

static const struct iio_info bmi270_info = {
	.read_raw = bmi270_read_raw,
	.write_raw = bmi270_write_raw,
	.read_avail = bmi270_read_avail,
};

int bmi270_core_probe(struct device *dev, struct regmap *regmap,
		      const char *name)
{
	struct iio_dev *indio_dev;
	struct bmi270_data *data;
	int ret;

	indio_dev = devm_iio_device_alloc(dev, sizeof(*data));
	if (!indio_dev)
		return -ENOMEM;

	data = iio_priv(indio_dev);
	data->regmap = regmap;
	mutex_init(&data->mutex);

	ret = iio_read_mount_matrix(dev, "mount-matrix", &data->orientation);
	if (ret)
		return ret;

	ret = bmi270_chip_init(data);
	if (ret) {
		dev_err(dev, "Failed to initialize BMI270: %d\n", ret);
		return ret;
	}

	indio_dev->name = name;
	indio_dev->modes = INDIO_DIRECT_MODE;
	indio_dev->info = &bmi270_info;
	indio_dev->channels = bmi270_channels;
	indio_dev->num_channels = ARRAY_SIZE(bmi270_channels);

	return devm_iio_device_register(dev, indio_dev);
}
EXPORT_SYMBOL_GPL(bmi270_core_probe);

MODULE_AUTHOR("OpenAI Codex");
MODULE_DESCRIPTION("Bosch BMI270 core driver");
MODULE_LICENSE("GPL");
