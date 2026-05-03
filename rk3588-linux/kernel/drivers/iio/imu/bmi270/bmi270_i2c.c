// SPDX-License-Identifier: GPL-2.0
/*
 * BMI270 - Bosch IMU, I2C frontend
 *
 * 7-bit I2C slave address is:
 *   - 0x68 if SDO is pulled low
 *   - 0x69 if SDO is pulled high
 */
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regmap.h>

#include "bmi270.h"

static const struct regmap_config bmi270_i2c_regmap_config = {
	.reg_bits = 8,
	.val_bits = 8,
};

static int bmi270_i2c_probe(struct i2c_client *client,
			    const struct i2c_device_id *id)
{
	struct regmap *regmap;
	const char *name = "bmi270";

	regmap = devm_regmap_init_i2c(client, &bmi270_i2c_regmap_config);
	if (IS_ERR(regmap)) {
		dev_err(&client->dev, "Failed to init i2c regmap: %ld\n",
			PTR_ERR(regmap));
		return PTR_ERR(regmap);
	}

	if (id)
		name = id->name;

	return bmi270_core_probe(&client->dev, regmap, name);
}

static const struct i2c_device_id bmi270_i2c_id[] = {
	{ "bmi270", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, bmi270_i2c_id);

#ifdef CONFIG_OF
static const struct of_device_id bmi270_of_match[] = {
	{ .compatible = "bosch,bmi270" },
	{ }
};
MODULE_DEVICE_TABLE(of, bmi270_of_match);
#endif

static struct i2c_driver bmi270_i2c_driver = {
	.driver = {
		.name = "bmi270_i2c",
		.of_match_table = of_match_ptr(bmi270_of_match),
	},
	.probe = bmi270_i2c_probe,
	.id_table = bmi270_i2c_id,
};
module_i2c_driver(bmi270_i2c_driver);

MODULE_AUTHOR("OpenAI Codex");
MODULE_DESCRIPTION("Bosch BMI270 I2C driver");
MODULE_LICENSE("GPL");
