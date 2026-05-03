# BMI270 Backport Notes for TOPEET RK3588

## Scope

This change backports BMI270 IIO support into the local `5.10.198` kernel tree
used by the TOPEET RK3588 SDK and wires a board-level device node onto the
`i2c2m4` pinmux path.

The first usable target is the user's hardware plan:

- Board: TOPEET RK3588
- Bus: `i2c2`
- Pinmux: `i2c2m4_xfer`
- Pins:
  - `U16-18` -> `I2C2_SCL_M4`
  - `U16-20` -> `I2C2_SDA_M4`

## Added Files

- `kernel/drivers/iio/imu/bmi270/Kconfig`
- `kernel/drivers/iio/imu/bmi270/Makefile`
- `kernel/drivers/iio/imu/bmi270/bmi270.h`
- `kernel/drivers/iio/imu/bmi270/bmi270_core.c`
- `kernel/drivers/iio/imu/bmi270/bmi270_i2c.c`
- `kernel/drivers/iio/imu/bmi270/bmi270_init_data.h`

## Modified Files

- `kernel/drivers/iio/imu/Kconfig`
- `kernel/drivers/iio/imu/Makefile`
- `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dts`
- `kernel/.config`

## Driver Design

This backport intentionally starts with a small, board-oriented feature set:

- I2C frontend only
- IIO raw/scale/sample-frequency support for:
  - accelerometer
  - gyroscope
  - temperature
- Bosch BMI270 init-data blob embedded into the driver tree
- no IRQ-triggered buffer path yet
- no step counter or motion-event path yet

That tradeoff keeps the code close to the local 5.10 IIO style and avoids
pulling in newer upstream helper patterns that are not needed for first bring-up.

## Source Basis

The implementation was derived from two upstream/official sources:

1. Linux upstream BMI270 driver model under `drivers/iio/imu/bmi270/`
2. Bosch Sensortec BMI270 Sensor API configuration data

## DTS Integration

The board DTS adds:

```dts
&i2c2 {
	bmi270@68 {
		compatible = "bosch,bmi270";
		reg = <0x68>;
		status = "okay";
		mount-matrix = "1", "0", "0",
			       "0", "1", "0",
			       "0", "0", "1";
	};
};
```

Notes:

- `0x68` is correct when the BMI270 `SDO` pin is strapped low.
- If your module straps `SDO` high, change `reg = <0x69>;`.
- The identity mount matrix is only a placeholder. If the sensor is mounted in
  a rotated orientation, update the matrix before relying on axis directions.

## Build Configuration

The local kernel `.config` is updated to enable:

```config
CONFIG_BMI270=y
CONFIG_BMI270_I2C=y
```

## Expected Runtime Interface

After boot, the sensor should enumerate through IIO. Typical sysfs paths look
like:

```text
/sys/bus/iio/devices/iio:deviceX/
```

Expected channels include:

- `in_accel_x_raw`
- `in_accel_y_raw`
- `in_accel_z_raw`
- `in_anglvel_x_raw`
- `in_anglvel_y_raw`
- `in_anglvel_z_raw`
- `in_temp_raw`

## Follow-up Work

If the hardware also exposes a BMI270 interrupt pin, the next clean extension is:

1. add an `interrupts` description in DTS
2. backport the data-ready trigger path
3. optionally backport motion and step-counter events
