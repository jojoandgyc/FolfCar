# RK3588 Golf Follow Car BSP 改板文件清单

本文档用于把当前 `rk3588-linux` BSP 从现有 `topeet` 板型迁移到你的 Golf Follow Car 开发板。

整理依据：

- 仓库当前 BSP
- 原理图 `Golf_Follow_Car_Project(2).pdf`
- 已渲染的原理图关键页：17/18/20/22/23/24

目标不是一次把所有外设都点亮，而是先把“板级配置入口、U-Boot、Kernel DTS、打包链路”全部梳理清楚，明确哪些文件必须改、为什么改、改哪里。

## 1. 先说结论

这套 BSP 当前默认板型是 `topeet-rk3588-linux`，但你的板子和它至少有 4 个关键差异：

1. 调试串口走 `UART2_M0`，原理图页 24 标成 `UART2_TX_M0_DEBUG` / `UART2_RX_M0_DEBUG`
2. TF 卡检测脚是 `SDMMC_DET_L`，插卡后为低电平，原理图页 20 已确认
3. TF 卡 3.3V 供电是直接接 `VCC_3V3_S3`，不是 Topeet DTS 里那种 GPIO 受控开关，原理图页 20 已确认
4. Type-C0 更像“USB2 OTG + CC 电阻”的简化方案，不是 Topeet DTS 里那套 `fusb302 + usb-c-connector + DP Altmode` 方案，原理图页 22/23 已确认

所以这次改板不建议直接在共享 `rk3588*.dtsi` 或 `topeet-*` 文件上硬改，建议新建一套你自己的板级文件。

## 2. 原理图确认的板级事实

| 项目 | 原理图结论 | 对 BSP 的影响 |
|---|---|---|
| SoC | RK3588 | 继续走 `rk3588` 家族即可 |
| DDR | LPDDR4，页 17 标注 `LPDDR4 200B 1x32bit` 两颗 | 第一版可以继续使用 RK 官方 LPDDR4 DDR bin |
| eMMC | 页 18，8bit，带 `DATA_STROBE`，IO 为 `VCC_1V8_S3`，Flash 供电 `VCC_3V3_S3` | U-Boot/Kernel 的 `sdhci` 需要 8bit、`non-removable`、HS400 1.8V |
| TF 卡 | 页 20，`SDMMC0_D0..D3/CMD/CLK`，CD 信号为 `SDMMC_DET_L`，并上拉到 1.8V | `cd-gpios` 必须配成 `GPIO_ACTIVE_LOW` |
| TF 供电 | 页 20，卡座 VDD 直接接 `VCC_3V3_S3` | 不应沿用 Topeet 的 `GPIO0_B7` 卡电源开关写法 |
| 调试串口 | 页 24，DEBUG 走 `UART2_M0` | `stdout-path`、FIQ debugger、U-Boot debug UART 都应锁定到 `uart2m0` |
| Recovery 键 | 页 24，`SARADC_VIN1_KEY/RECOVERY` | Kernel/U-Boot 可保留 `adc-keys` |
| Maskrom 键 | 页 24，`BOOT_SARADC_IN0` | 这是进 Maskrom 的硬件条件，不需要专门写驱动，但文档要写验证方法 |
| Type-C0 | 页 23/22，`TYPEC0_OTG_DP/DM`，CC 电阻直连，烧录时建议双供电 | 不能直接照搬 Topeet 的 `fusb302/typec altmode` 逻辑 |
| USB Host | 页 23，有独立 `USB_HOST`/`USB20_HOST0_DP/DM` 口 | Kernel DTS 里 USB host 节点要按实际口型启用 |

## 3. 改板原则

建议按下面的方式迁移：

- 保留官方/Topeet 公共文件做参考
- 新建你自己的板级文件
- 只在“板级入口”处切换到新文件
- 尽量不改共享 `rk3588-u-boot.dtsi`、`rk3588-linux.dtsi` 这类通用文件

推荐新板命名统一成：

- SDK defconfig: `rockchip_rk3588_golf_follow_car_defconfig`
- U-Boot defconfig: `rk3588_golf_follow_car_defconfig`
- U-Boot DTS: `rk3588-golf-follow-car.dts`
- Kernel DTS: `golf-follow-car-rk3588.dts`
- Kernel 公共板级 dtsi: `golf-follow-car-rk3588.dtsi`

## 4. 必须修改的文件

下面这些文件属于“要做成你自己的 BSP，基本都要动”的部分。

| 文件 | 建议动作 | 为什么要改 | 具体改哪里 |
|---|---|---|---|
| `device/rockchip/.chips/rk3588/rockchip_rk3588_topeet_defconfig` | 更推荐复制为新文件，而不是直接改 | 这是 SDK 顶层板型入口，决定 U-Boot/Kernel 用哪个配置 | 新建 `rockchip_rk3588_golf_follow_car_defconfig`，至少改 `RK_KERNEL_DTS_NAME`、`RK_UBOOT_CFG` |
| `device/rockchip/common/scripts/build.sh` | 可选修改 | 当前脚本把默认板型硬编码成 `rockchip_rk3588_topeet_defconfig` | 把 `run_build_hooks init rockchip_rk3588_topeet_defconfig` 改成你的新 defconfig；如果你接受每次手动指定板型，这个文件也可以先不改 |
| `u-boot/configs/rk3588_golf_follow_car_defconfig` | 新建 | 当前 `rk3588_defconfig` 仍默认指向 `rk3588-evb` 设备树 | 从 `u-boot/configs/rk3588_defconfig` 复制，新设 `CONFIG_DEFAULT_DEVICE_TREE`、`CONFIG_OF_LIST` |
| `u-boot/arch/arm/dts/rk3588-golf-follow-car.dts` | 新建 | U-Boot 阶段必须有你自己的板级设备树，尤其是串口、eMMC、TF 检测极性 | 从 `rk3588-evb.dts` 或最小骨架开始，覆盖 `chosen`、`uart2`、`sdhci`、`sdmmc` |
| `u-boot/arch/arm/dts/Makefile` | 修改 | 让新 U-Boot DTB 被编译系统识别 | 新增 `rk3588-golf-follow-car.dtb` |
| `kernel/arch/arm64/boot/dts/rockchip/golf-follow-car-rk3588.dts` | 新建 | Kernel 不能继续用 `topeet-rk3588-linux.dts`，否则会带入大量参考板外设配置 | 以 `topeet-rk3588-linux.dts` 为参考，保留共性，删掉不属于你板子的节点 |
| `kernel/arch/arm64/boot/dts/rockchip/golf-follow-car-rk3588.dtsi` | 新建 | Topeet 的公共板级 dtsi 已经夹带了 Type-C、SD 电源控制等与你板子不符的内容 | 以 `topeet-rk3588-linux.dtsi` 为模板重写板级电源/USB/SD/eMMC 相关节点 |
| `kernel/arch/arm64/boot/dts/rockchip/Makefile` | 修改 | 让新 kernel dtb 能被编译 | 新增 `golf-follow-car-rk3588.dtb` |

## 5. 每个必须改文件要怎么改

### 5.1 SDK 板型入口

文件：

- `device/rockchip/.chips/rk3588/rockchip_rk3588_golf_follow_car_defconfig`（建议新建）

建议从当前文件复制：

- `device/rockchip/.chips/rk3588/rockchip_rk3588_topeet_defconfig`

至少要改成下面这样：

```bash
RK_WIFIBT_CHIP="RTL8723DU"
RK_KERNEL_DTS_NAME="golf-follow-car-rk3588"
RK_UBOOT_CFG="rk3588_golf_follow_car"
RK_USE_FIT_IMG=y
```

说明：

- `RK_KERNEL_DTS_NAME` 决定内核最终使用哪个 DTS
- `RK_UBOOT_CFG` 决定 SDK 最后去编哪一个 U-Boot defconfig
- `RK_WIFIBT_CHIP` 只有在你板上无线模组确实还是 `RTL8723DU` 时才能保留；如果模组不同，这里也要一起改

`build.sh` 里当前默认板型是：

```bash
run_build_hooks init rockchip_rk3588_topeet_defconfig
```

如果你想以后直接 `./build.sh` 就编自己的板子，这里要改成：

```bash
run_build_hooks init rockchip_rk3588_golf_follow_car_defconfig
```

### 5.2 U-Boot defconfig

文件：

- `u-boot/configs/rk3588_golf_follow_car_defconfig`（新建）

建议来源：

- `u-boot/configs/rk3588_defconfig`

必须确认/修改的配置：

```text
CONFIG_DEFAULT_DEVICE_TREE="rk3588-golf-follow-car"
CONFIG_OF_LIST="rk3588-golf-follow-car"
CONFIG_BAUDRATE=115200
CONFIG_DEBUG_UART_BASE=0xFEB50000
CONFIG_ROCKCHIP_UART_MUX_SEL_M=0
```

为什么：

- `0xFEB50000` 对应 UART2
- `MUX_SEL_M=0` 对应 `UART2_M0`
- 这和原理图页 24 的 DEBUG 串口完全一致

### 5.3 U-Boot 板级 DTS

文件：

- `u-boot/arch/arm/dts/rk3588-golf-follow-car.dts`（新建）

这里至少要处理 4 个点：

1. `chosen.stdout-path = &uart2`
2. `&uart2` 绑定 `uart2m0_xfer`
3. `&sdhci` 配 eMMC 8bit/HS400/non-removable
4. `&sdmmc` 的 `cd-gpios` 改成低有效

建议重点改这些节点：

```dts
/ {
	aliases {
		mmc0 = &sdhci;
		mmc1 = &sdmmc;
	};

	chosen {
		stdout-path = &uart2;
		u-boot,spl-boot-order = &sdmmc, &sdhci, &spi_nand, &spi_nor;
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
	non-removable;
	mmc-hs400-1_8v;
	mmc-hs400-enhanced-strobe;
	u-boot,dm-spl;
	status = "okay";
};

&sdmmc {
	bus-width = <4>;
	cd-gpios = <&gpio0 RK_PA4 GPIO_ACTIVE_LOW>;
	u-boot,dm-spl;
	status = "okay";
};
```

为什么：

- 页 20 明确写了 `SDMMC_DET_L`，所以不能继续沿用当前共享 `rk3588-u-boot.dtsi` 里的 `GPIO_ACTIVE_HIGH`
- 页 18 的 eMMC 是 8bit + data strobe，继续走 HS400 是合理的

注意：

- 不建议直接改共享文件 `u-boot/arch/arm/dts/rk3588-u-boot.dtsi`
- 正确做法是在你自己的 `rk3588-golf-follow-car.dts` 里覆盖共享默认值

### 5.4 Kernel 顶层 DTS

文件：

- `kernel/arch/arm64/boot/dts/rockchip/golf-follow-car-rk3588.dts`（新建）

建议来源：

- `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dts`

这个文件不要直接照抄，原因很简单：Topeet 顶层 dts 里已经带了很多你板子未必有的外设。

你至少要逐项确认这些节点是否真的存在于你的板子：

- `es8388_sound`
- `rk_headset`
- `fan`
- `leds`
- `dht11`
- `hym8563`
- `sata0`
- `pcie3x4`
- `gmac0`
- `gmac1`
- `hdmirx_ctrler`
- 屏幕相关 `topeet-screen-lcds.dts`
- 摄像头相关 `topeet-camera-config.dtsi`

处理原则：

- 确认板上没有，就删掉 include 或把节点 `status = "disabled"`
- 只保留原理图能确认存在的外设

### 5.5 Kernel 公共板级 dtsi

文件：

- `kernel/arch/arm64/boot/dts/rockchip/golf-follow-car-rk3588.dtsi`（新建）

建议来源：

- `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dtsi`

这是整个迁移里最关键的文件之一，因为 Topeet 版本里至少有 3 处与你板子明显不一致。

#### A. TF 卡供电写法要改

Topeet 当前写法：

- `vcc_3v3_sd_s0` 用 `GPIO0_B7` 控制
- `sdmmc` 用 `vmmc-supply = <&vcc_3v3_sd_s0>`

你的原理图页 20 显示：

- TF VDD 直接接 `VCC_3V3_S3`
- 没看到受控开关

所以建议改成固定 3.3V regulator：

```dts
vcc_3v3_sd_s0: vcc-3v3-sd-s0-regulator {
	compatible = "regulator-fixed";
	regulator-name = "vcc_3v3_sd_s0";
	regulator-always-on;
	regulator-boot-on;
	regulator-min-microvolt = <3300000>;
	regulator-max-microvolt = <3300000>;
};
```

同时删掉或不要继承：

- `gpio = <&gpio0 RK_PB7 GPIO_ACTIVE_HIGH>;`
- `pinctrl-0 = <&sd_s0_pwr>;`
- `sd_s0_pwr` 这个 pinctrl 定义

#### B. TF 卡检测极性要改

你的板子页 20 是 `SDMMC_DET_L`，插卡拉低。

所以 `&sdmmc` 节点建议改成：

```dts
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

#### C. Type-C/USB 逻辑大概率要重写

Topeet 现在带了下面这些节点：

- `fusb302@22`
- `usb-c-connector`
- `orientation-switch`
- `dp_altmode_mux`
- `vbus5v0_typec`
- `typec5v_pwren`
- `usbdp_phy0` 的 Type-C/DP Altmode 配置

而你的原理图页 22/23 更接近：

- Type-C0 只是 USB2 OTG
- CC 靠电阻
- 没看到 `fusb302`
- 没看到 DP Altmode 芯片链路

所以这部分至少要做一件事：

- 不要把 Topeet 的 Type-C 控制器配置原样继承过来

建议处理方式：

1. 在你的新 `golf-follow-car-rk3588.dtsi` 里删除 `fusb302` 相关节点
2. 删除 `usb-c-connector`、`orientation-switch`、`dp_altmode_mux`
3. 保留最基础的 `u2phy0_otg` / `usbdrd_dwc3_0` 或实际使用的 USB2 OTG 控制器
4. Host 口按页 23 的 `USB_HOST`、`USB20_HOST0_DP/DM` 实际接法启用

这部分如果不改，最容易出现的现象是：

- Type-C 角色判断异常
- USB OTG 不枚举
- DTS 里引用了硬件上根本不存在的 I2C 设备

### 5.6 Kernel Makefile

文件：

- `kernel/arch/arm64/boot/dts/rockchip/Makefile`

当前只有：

```make
dtb-$(CONFIG_ARCH_ROCKCHIP) += topeet-rk3588-linux.dtb
```

你需要追加：

```make
dtb-$(CONFIG_ARCH_ROCKCHIP) += golf-follow-car-rk3588.dtb
```

## 6. 条件修改文件

下面这些文件不是第一阶段必改，但一旦遇到对应问题，就要动。

| 文件 | 什么时候改 | 为什么改 | 改哪里 |
|---|---|---|---|
| `rkbin/tools/ddrbin_param.txt` | DDR log 出不来，且确认串口硬件已通时 | DDR bin 的调试串口/波特率可能不匹配 | 设成 `uart id=2`、`uart iomux=0`、`uart baudrate=115200` |
| `rkbin/RKBOOT/RK3588MINIALL.ini` | 你重新生成了自定义 DDR bin 时 | Loader 需要引用新的 DDR bin | 改 `Path1` 和 `FlashData` |
| `device/rockchip/.chips/rk3588/parameter.txt` | 分区布局、boot/recovery/rootfs 大小要变时 | 决定烧写分区和镜像偏移 | 改 `CMDLINE: mtdparts=...` |
| `rkbin/RKTRUST/RK3588TRUST.ini` | 你启用了安全启动/替换 BL31/BL32 时 | Trust 镜像会跟着变 | 改 `BL31_OPTION` / `BL32_OPTION` |
| `topeet-screen-lcds.dts` 对应替代文件 | 你的板子实际带 LCD 时 | 现有屏参不一定匹配 | 新建你自己的屏参文件并替换 include |
| `topeet-camera-config.dtsi` 对应替代文件 | 你的板子实际挂了摄像头时 | sensor/I2C/电源脚大概率不同 | 新建你自己的 camera dtsi |

## 7. 不建议直接改的文件

这些文件可以参考，但不建议直接动：

- `u-boot/arch/arm/dts/rk3588-u-boot.dtsi`
- `kernel/arch/arm64/boot/dts/rockchip/rk3588-linux.dtsi`
- `u-boot/configs/rk3588_defconfig`
- `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dts`
- `kernel/arch/arm64/boot/dts/rockchip/topeet-rk3588-linux.dtsi`

原因：

- 这些要么是共享文件，要么是当前参考板文件
- 直接改会把“公共 SoC 配置”和“你自己的板级差异”混在一起
- 后面维护会非常痛苦

## 8. 推荐的实际改法顺序

建议按下面顺序推进：

1. 新建 SDK defconfig，切走 `topeet`
2. 新建 U-Boot defconfig
3. 新建 U-Boot DTS，只先保证串口、eMMC、TF
4. 新建 Kernel DTS/DTSI，只保留你板上实际存在的外设
5. 优先修正 TF 卡 CD 极性和 TF 电源模型
6. 清理 Topeet 的 `fusb302/typec altmode` 逻辑
7. 烧录后先验证串口、Maskrom、U-Boot、eMMC、TF
8. 再补网口、USB host、LCD、camera、audio

## 9. 第一阶段验证清单

做完上面的修改后，至少要验证这些：

- 串口上能稳定看到 DDR log 和 U-Boot log
- `MASKROM_KEY` 能把板子拉进 Maskrom
- `rkdeveloptool` 能识别设备
- U-Boot 下 `mmc list` 能看到 eMMC 和 TF
- 插拔 TF 卡时，`mmc dev 1` 行为正常
- Kernel 启动后 `dmesg | grep mmc` 没有 CD 极性错误
- Type-C0 至少能按你的目标模式工作（OTG 或烧录）

## 10. 这次迁移里最容易漏掉的点

最后提醒 5 个高风险点：

1. `output/.config` 是自动生成文件，不要手改，要改源 defconfig
2. U-Boot 和 Kernel 都要同时切到你自己的板级 DTS，不能只改一边
3. `SDMMC_DET_L` 一定要配低有效，这是这份原理图里已经实锤的点
4. Topeet 的 `fusb302 + usb-c-connector + DP altmode` 很可能不适合你的板子
5. 页 22 已写明 eMMC 烧录建议“双供电”，这不是软件改动，但它会直接影响你调试时对“烧录失败”的判断

---

如果后续你要我继续往下做，我建议下一步直接帮你把这份文档里的“必须修改文件”对应的骨架文件都创建出来。
