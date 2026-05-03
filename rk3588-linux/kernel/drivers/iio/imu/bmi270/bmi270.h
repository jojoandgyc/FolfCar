/* SPDX-License-Identifier: GPL-2.0 */
#ifndef BMI270_H_
#define BMI270_H_

#include <linux/iio/iio.h>
#include <linux/mutex.h>

struct device;
struct regmap;

struct bmi270_data {
	struct regmap *regmap;
	struct iio_mount_matrix orientation;
	struct mutex mutex;
};

int bmi270_core_probe(struct device *dev, struct regmap *regmap,
		      const char *name);

#endif /* BMI270_H_ */
