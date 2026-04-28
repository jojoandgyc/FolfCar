# RK3588 Golf Follow Car U-Boot Bring-up 修改清单

本文档根据当前 BSP 仓库、`Golf_Follow_Car_Project(2).pdf` 原理图和 `RK3588_Ubuntu22.04LTS_bringup_custom.md` 整理。目标是先让新板稳定进入 U-Boot 命令行，并能在 U-Boot 中看到 eMMC/TF。

当前结论：这个 BSP 顶层构建脚本默认使用 `rockchip_rk3588_topeet_defconfig`，但是 U-Boot 仍使用通用 `rk3588-evb` 设备树。为了适配 Golf Follow Car 板，必须给 U-Boot 建立独立 defconfig 和独立 DTS，至少修正调试串口、启动介质和 TF card-detect 极性。

## 1. 原理图确认的板级事实

| 模块 | 原理图事实 | BSP 影响 |
|---|---|---|
| SoC | RK3588 | 继续使用 `RK_CHIP_FAMILY=rk3588` 默认链路。 |
| DDR | LPDDR4，原理图页 17 标注 `LPDDR4 200B 1x32bit` 两颗 | 现有 `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin` 可以作为第一版 DDR bin。若 DDR log 不出来，再改 DDR bin 的 UART 参数。 |
| PMIC | RK806 + RK8602/RK8603/RK8602 外置 Buck | Kernel DTS 已有 RK806/RK860x 结构；U-Boot 第一阶段不强制完整 regulator 移植，但保留后续检查项。 |
| 调试串口 | DEBUG 推荐焊 `UART2_TX_M0_DEBUG` / `UART2_RX_M0_DEBUG`，对应 `UART2_M0`，SoC 管脚 `GPIO0_B5/B6` | U-Boot `stdout-path` 用 `uart2`，pinctrl 用 `uart2m0_xfer`，波特率按现有 BSP 使用 `115200`。 |
| Maskrom 键 | `BOOT_SARADC_IN0` 按键拉地 | 属于 BootROM 入口条件；U-Boot DTS 不需要控制，但文档和验证步骤要写清。 |
| Recovery 键 | `SARADC_VIN1_KEY/RECOVERY` | 可保留 U-Boot `adc-keys`，不影响进入 U-Boot。 |
| eMMC | 8-bit eMMC，`EMMC_D0..D7/CMD/CLKOUT/DATA_STROBE/RSTN`，eMMC IO 1.8V | U-Boot `sdhci` 需要 `bus-width=<8>`、`non-removable`、`mmc-hs400-1_8v`、`mmc-hs400-enhanced-strobe`。 |
| TF 卡 | SDMMC0，`SDMMC0_D0..D3/CMD/CLK`；CD 为 `SDMMC_DET_L`，插卡后为低电平；卡座 VDD 直接接 `VCC_3V3_S3` | U-Boot `sdmmc` 的 `cd-gpios` 必须是 `GPIO_ACTIVE_LOW`。现有通用 U-Boot DTS 写成了 `GPIO_ACTIVE_HIGH`，需要修正。 |
| USB 下载口 | Type-C0 USB2 OTG，`TYPEC0_OTG_DP/DM`；原理图提示 eMMC 烧录时需要一路下载口加一路供电 | Maskrom/rkdeveloptool 验证时接 Type-C0，并保证外部供电。 |

## 2. 当前 BSP 关键路径

| 当前文件 | 当前状态 | 判断 |
|---|---|---|
| `device/rockchip/common/scripts/build.sh` | 当前第 140 行固定 `run_build_hooks init rockchip_rk3588_topeet_defconfig` | 当前仓库被定制为 Topeet 默认板型。最小改法可继续使用这个 SDK defconfig，只把其中 U-Boot 配置指向新 U-Boot defconfig。 |
| `device/rockchip/.chips/rk3588/rockchip_rk3588_topeet_defconfig` | 只有 `RK_WIFIBT_CHIP`、`RK_KERNEL_DTS_NAME`、`RK_USE_FIT_IMG` | 没有显式 `RK_UBOOT_CFG`，因此 U-Boot 默认走 `rk3588_defconfig`。 |
| `u-boot/configs/rk3588_defconfig` | `CONFIG_DEFAULT_DEVICE_TREE="rk3588-evb"`；`CONFIG_OF_LIST="rk3588-evb"`；`CONFIG_DEBUG_UART_BASE=0xFEB50000`；`CONFIG_BAUDRATE=115200` | UART2 基地址和 115200 正确，但设备树仍是 EVB，需要复制成自定义 defconfig。 |
| `u-boot/arch/arm/dts/rk3588-u-boot.dtsi` | `stdout-path = &uart2`；`u-boot,spl-boot-order = &sdmmc, &sdhci`；`cd-gpios = <&gpio0 RK_PA4 GPIO_ACTIVE_HIGH>` | 串口和启动顺序基本可用；TF CD 极性与原理图相反。不要直接改共享 dtsi，建议在自定义 DTS 中覆盖。 |
| `rkbin/RKBOOT/RK3588MINIALL.ini` | DDR bin 为 `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin`，SPL 为 `rk3588_spl_v1.13.bin` | 与 RK3588 + LPDDR4 第一版 bring-up 匹配，先不改。 |
| `rkbin/RKTRUST/RK3588TRUST.ini` | BL31 为 `rk3588_bl31_v1.45.elf`，BL32 为 `rk3588_bl32_v1.15.bin` | 先不改。 |
| `device/rockchip/.chips/rk3588/parameter.txt` | `uboot` 起始 `0x4000`，`boot` 起始 `0x8000` | 与开发指导文档的 Rockchip 常用偏移一致，进入 U-Boot 阶段无需修改。 |

## 3. 必须修改的文件

### 3.1 `device/rockchip/.chips/rk3588/rockchip_rk3588_topeet_defconfig`

最小改法是在现有默认板型中增加 U-Boot 配置指向：

```bash
RK_WIFIBT_CHIP="RTL8723DU"
RK_KERNEL_DTS_NAME="topeet-rk3588-linux"
RK_UBOOT_CFG="rk3588_golf_follow_car"
RK_USE_FIT_IMG=y
```

说明：

- `RK_UBOOT_CFG` 会让 SDK 调用 `u-boot/configs/rk3588_golf_follow_car_defconfig`。
- 当前目标只是进 U-Boot，`RK_KERNEL_DTS_NAME` 可以先不动。
- 如果后续要把 Topeet 名称清掉，建议新建 `rockchip_rk3588_golf_follow_car_defconfig`，并把 `device/rockchip/common/scripts/build.sh` 第 140 行改为：

```bash
run_build_hooks init rockchip_rk3588_golf_follow_car_defconfig
```

### 3.2 `u-boot/configs/rk3588_golf_follow_car_defconfig`

新建文件，来源为：

```bash
cp u-boot/configs/rk3588_defconfig u-boot/configs/rk3588_golf_follow_car_defconfig
```

在新文件中修改以下项：

```text
CONFIG_DEFAULT_DEVICE_TREE="rk3588-golf-follow-car"
CONFIG_OF_LIST="rk3588-golf-follow-car"
CONFIG_BAUDRATE=115200
CONFIG_DEBUG_UART_BASE=0xFEB50000
CONFIG_ROCKCHIP_UART_MUX_SEL_M=0
```

说明：

- `0xFEB50000` 是 UART2，匹配原理图 DEBUG 口。
- `MUX_SEL_M=0` 对应 `UART2_M0`，匹配 `GPIO0_B5/B6`。
- `CONFIG_BAUDRATE=115200` 与当前 kernel `fiq-debugger` 配置一致。若实测 DDR bin 或串口工具固定为 1500000，需要 U-Boot 和 kernel 同步改。

### 3.3 `u-boot/arch/arm/dts/rk3588-golf-follow-car.dts`

新建 U-Boot 板级 DTS。建议不要直接修改 `rk3588-evb.dts` 或共享的 `rk3588-u-boot.dtsi`。

建议内容骨架如下：

```dts
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)

/dts-v1/;
#include "rk3588.dtsi"
#include "rk3588-u-boot.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
	model = "Golf Follow Car RK3588 Board";
	compatible = "golf,follow-car-rk3588", "rockchip,rk3588";

	aliases {
		mmc0 = &sdhci;
		mmc1 = &sdmmc;
	};

	chosen {
		stdout-path = &uart2;
		u-boot,spl-boot-order = &sdmmc, &sdhci, &spi_nand, &spi_nor;
	};

	adc-keys {
		compatible = "adc-keys";
		io-channels = <&saradc 1>;
		io-channel-names = "buttons";
		keyup-threshold-microvolt = <1800000>;
		u-boot,dm-pre-reloc;
		status = "okay";

		recovery-key {
			u-boot,dm-pre-reloc;
			linux,code = <KEY_VOLUMEUP>;
			label = "recovery";
			press-threshold-microvolt = <17000>;
		};
	};
};

&uart2 {
	pinctrl-names = "default";
	pinctrl-0 = <&uart2m0_xfer>;
	u-boot,dm-spl;
	status = "okay";
};

&sdhci {
	bus-width = <8>;
	u-boot,dm-spl;
	mmc-hs400-1_8v;
	mmc-hs400-enhanced-strobe;
	non-removable;
	status = "okay";
};

&sdmmc {
	bus-width = <4>;
	u-boot,dm-spl;
	cd-gpios = <&gpio0 RK_PA4 GPIO_ACTIVE_LOW>;
	status = "okay";
};
```

关键修改点：

- `stdout-path = &uart2`：匹配 DEBUG 口。
- `pinctrl-0 = <&uart2m0_xfer>`：匹配原理图的 `UART2_TX_M0_DEBUG` 和 `UART2_RX_M0_DEBUG`。
- `cd-gpios = <&gpio0 RK_PA4 GPIO_ACTIVE_LOW>`：匹配 TF 卡 `SDMMC_DET_L`，插卡低电平。
- `aliases` 保持 `mmc0 = &sdhci`、`mmc1 = &sdmmc`，U-Boot 命令中 eMMC 通常为 `mmc 0`，TF 为 `mmc 1`。
- `u-boot,spl-boot-order` 保持 TF 优先，方便插 TF 救砖；量产阶段如需 eMMC 优先，可改为 `<&sdhci>, <&sdmmc>`。

### 3.4 `u-boot/arch/arm/dts/Makefile`

多数情况下 `CONFIG_DEFAULT_DEVICE_TREE` 可以直接构建指定 DTS。为了让 `make dtbs` 和 IDE/脚本扫描也能看到新 DTB，建议把新 DTB 加入 Rockchip 列表。

在 `dtb-$(CONFIG_ARCH_ROCKCHIP) +=` 列表中增加：

```make
	rk3588-golf-follow-car.dtb \
```

如果不加这个文件，`./make.sh rk3588_golf_follow_car` 通常仍可通过 `DEVICE_TREE` 路径构建；但加上更稳。

## 4. 条件修改文件：DDR 串口或 DDR training 异常时再改

### 4.1 `rkbin/tools/ddrbin_param.txt`

只有当 `rkdeveloptool db MiniLoaderAll.bin` 后完全没有 DDR log，且硬件串口确认正常时，再修改 DDR bin 参数。

按原理图 DEBUG 口设置：

```text
uart id=2
uart iomux=0
uart baudrate=115200
```

参考 `rkbin/tools/ddrbin_tool_user_guide.txt`：`uart id=2` 是 UART2，`uart iomux=0` 是 UART2_M0，波特率只建议 `115200` 或 `1500000`。

生成自定义 DDR bin 的流程建议是复制原 bin 后原地修改副本：

```bash
cp rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin \
   rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_golf_uart2m0_115200.bin

rkbin/tools/ddrbin_tool rk3588 \
  rkbin/tools/ddrbin_param.txt \
  rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_golf_uart2m0_115200.bin
```

### 4.2 `rkbin/RKBOOT/RK3588MINIALL.ini`

如果生成了上面的自定义 DDR bin，则把两处 DDR bin 路径改成自定义文件：

```ini
[CODE471_OPTION]
Path1=bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_golf_uart2m0_115200.bin

[LOADER_OPTION]
FlashData=bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_golf_uart2m0_115200.bin
```

如果现有 DDR bin 已有 DDR log 且 training 通过，不要先改这里。

## 5. 后续进 Linux 前建议同步修改

这些不是进入 U-Boot 的硬性条件，但如果下一步要从 U-Boot 拉起 Ubuntu，需要一起修。

### 5.1 `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dtsi`

当前 `&sdmmc` 没有写 `cd-gpios`，且 `vcc_3v3_sd_s0` 用了 `GPIO0_B7` 做 SD 电源使能。但原理图页 20 显示 TF 卡 VDD 直接接 `VCC_3V3_S3`，CD 是 `SDMMC_DET_L` 低有效。

建议修改：

```dts
vcc_3v3_sd_s0: vcc-3v3-sd-s0-regulator {
	compatible = "regulator-fixed";
	regulator-name = "vcc_3v3_sd_s0";
	regulator-always-on;
	regulator-boot-on;
	regulator-min-microvolt = <3300000>;
	regulator-max-microvolt = <3300000>;
};

&sdmmc {
	max-frequency = <150000000>;
	no-sdio;
	no-mmc;
	bus-width = <4>;
	cap-mmc-highspeed;
	cap-sd-highspeed;
	disable-wp;
	sd-uhs-sdr104;
	cd-gpios = <&gpio0 RK_PA4 GPIO_ACTIVE_LOW>;
	vmmc-supply = <&vcc_3v3_sd_s0>;
	status = "okay";
};
```

说明：

- 删除或停用原来的 `gpio = <&gpio0 RK_PB7 GPIO_ACTIVE_HIGH>` 和 `pinctrl-0 = <&sd_s0_pwr>`，因为原理图没有看到 TF VDD 由该 GPIO 控制。
- 如果实板上后续补了电源开关，再按实物改回 `gpio` 控制。

### 5.2 `kernel/arch/arm64/boot/dts/rockchip/rk3588-linux.dtsi`

当前 `fiq-debugger` 已经是：

```dts
rockchip,serial-id = <2>;
rockchip,baudrate = <115200>;
pinctrl-0 = <&uart2m0_xfer>;
```

这与原理图 DEBUG 口一致，进入 U-Boot 目标下无需修改。

## 6. 明确不建议改的共享文件

| 文件 | 原因 |
|---|---|
| `u-boot/arch/arm/dts/rk3588-evb.dts` | EVB 参考板文件，直接改会污染参考配置。 |
| `u-boot/arch/arm/dts/rk3588-u-boot.dtsi` | 共享 RK3588 U-Boot 早期设备树；本板只需要在自定义 DTS 中覆盖 `sdmmc` CD 极性。 |
| `u-boot/configs/rk3588_defconfig` | 共享 RK3588 默认配置；复制成 `rk3588_golf_follow_car_defconfig` 更容易回退和比对。 |
| `rkbin/RKTRUST/RK3588TRUST.ini` | BL31/BL32 当前版本与 RK3588 匹配，进入 U-Boot 阶段没有证据需要修改。 |
| `device/rockchip/.chips/rk3588/parameter.txt` | 当前 `uboot`/`boot` 分区偏移符合 bring-up 文档常用布局。 |

## 7. 构建和烧录验证

### 7.1 构建

```bash
cd /home/jojo/rk3588liunx/rk3588-linux
./build.sh uboot
./build.sh firmware
```

期望 `rockdev/` 下出现：

```text
MiniLoaderAll.bin
uboot.img
trust.img
parameter.txt
```

### 7.2 Maskrom 入口

硬件动作：

1. 接 DEBUG 串口到 H1/J2 对应的 UART2_M0 调试口，串口参数 `115200 8N1`。
2. 接 Type-C0 下载口到 PC。
3. 按住 `MASKROM_KEY`，再复位或上电。
4. 原理图页 22 提醒 eMMC 烧录时需要保证额外供电，不要只依赖下载口。

主机验证：

```bash
rkdeveloptool ld
```

### 7.3 烧录最小 U-Boot 镜像

使用 SDK 自带 `upgrade_tool` 路线：

```bash
./rkflash.sh loader
./rkflash.sh parameter
./rkflash.sh uboot
./rkflash.sh trust
```

如果只想临时下载 loader 验证 DDR log：

```bash
tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool ul rockdev/MiniLoaderAll.bin
```

### 7.4 U-Boot 命令行检查

进入 U-Boot 后执行：

```bash
printenv
bdinfo
mmc list
mmc dev 0
mmc info
mmc dev 1
mmc info
```

预期：

- 串口能看到 U-Boot banner 和命令行。
- `mmc 0` 看到 eMMC。
- 插入 TF 后 `mmc 1` 看到 TF 卡。
- 如果 `mmc 1` 不出现，优先查 `cd-gpios` 是否仍是 `GPIO_ACTIVE_HIGH`、TF 卡座 CD 是否焊接、`SDMMC_DET_L` 是否插卡拉低。

## 8. 最小修改清单汇总

必须改：

| 文件 | 操作 |
|---|---|
| `device/rockchip/.chips/rk3588/rockchip_rk3588_topeet_defconfig` | 增加 `RK_UBOOT_CFG="rk3588_golf_follow_car"`。 |
| `u-boot/configs/rk3588_golf_follow_car_defconfig` | 新建，复制 `rk3588_defconfig`，修改 `CONFIG_DEFAULT_DEVICE_TREE` 和 `CONFIG_OF_LIST`。 |
| `u-boot/arch/arm/dts/rk3588-golf-follow-car.dts` | 新建，定义板名、UART2_M0、eMMC、TF，修正 `cd-gpios` 为低有效。 |
| `u-boot/arch/arm/dts/Makefile` | 建议增加 `rk3588-golf-follow-car.dtb`。 |

条件改：

| 文件 | 条件 |
|---|---|
| `rkbin/tools/ddrbin_param.txt` | 无 DDR log 或 DDR bin 串口参数明显不匹配时。 |
| `rkbin/RKBOOT/RK3588MINIALL.ini` | 只有使用自定义 DDR bin 时，才替换 `Path1` 和 `FlashData`。 |
| `device/rockchip/common/scripts/build.sh` | 只有采用新 SDK 板型 `rockchip_rk3588_golf_follow_car_defconfig` 时，把第 140 行默认板型从 Topeet 改成 Golf。 |

后续进 Linux 建议改：

| 文件 | 操作 |
|---|---|
| `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dtsi` | 修正 TF 电源 regulator 和 `cd-gpios = <&gpio0 RK_PA4 GPIO_ACTIVE_LOW>`。 |

