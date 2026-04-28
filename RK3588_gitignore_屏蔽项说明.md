# RK3588 项目 `.gitignore` 屏蔽项说明

这份文档解释当前 `.gitignore` 中各类屏蔽规则的作用，以及为什么建议屏蔽它们。

核心原则：

> GitHub 仓库中应该主要保存源码、配置、脚本、补丁和说明文档；不建议保存 rootfs、系统镜像、工具链、缓存、编译输出、大型二进制文件。

你之前遇到的错误：

```text
remote: fatal: pack exceeds maximum allowed size (2.00 GiB)
```

说明本地 Git 提交包超过了 GitHub 单次接收限制。  
因此需要通过 `.gitignore` 排除不适合提交的大文件和生成文件。

---

## 1. Ubuntu / Debian rootfs 和生成出来的文件系统

```gitignore
rk3588-linux/ubuntu/binary/
rk3588-linux/ubuntu/cache/
rk3588-linux/ubuntu/rootfs/
rk3588-linux/ubuntu/rootfs.img
rk3588-linux/ubuntu/*.tar.xz
rk3588-linux/debian/*.tar.xz
```

### `rk3588-linux/ubuntu/binary/`

这是 Ubuntu 根文件系统展开后的目录，里面通常包含：

```text
/bin
/usr
/lib
/var
/etc
```

也就是一整个 Ubuntu 系统目录结构。

你之前遇到的权限问题就来自这里：

```text
rk3588-linux/ubuntu/binary/var/lib/snapd/void/
Permission denied
```

### 为什么屏蔽？

因为它是生成出来的系统文件，不是源码。里面文件数量巨大、权限复杂，还可能包含软链接、设备文件、缓存、系统目录等。  
放进 GitHub 会导致仓库体积过大，也容易出现权限问题。

---

### `rk3588-linux/ubuntu/cache/`

这是构建 Ubuntu rootfs 时产生的缓存目录。

### 为什么屏蔽？

缓存文件可以重新下载或重新生成，不应该提交。  
它会让仓库变大，但对源码管理没有意义。

---

### `rk3588-linux/ubuntu/rootfs/`

这是制作系统镜像时展开出来的根文件系统目录。

### 为什么屏蔽？

它和 `ubuntu/binary/` 类似，属于生成结果，不是源码。

---

### `rk3588-linux/ubuntu/rootfs.img`

这是完整的 Ubuntu rootfs 镜像文件。你之前查到它大约 5GB：

```text
5061476352 ./rk3588-linux/ubuntu/rootfs.img
```

### 为什么屏蔽？

GitHub 普通 Git 仓库不适合放这种系统镜像文件。  
它一个文件就非常大，会直接导致 push 失败。

---

### `rk3588-linux/ubuntu/*.tar.xz`

例如：

```text
ubuntu-jammy-gnome-arm64.tar.xz
ubuntu-jammy-xfce-arm64.tar.xz
ubuntu-focal-xfce-arm64.tar.xz
```

这些是 Ubuntu rootfs 压缩包。

### 为什么屏蔽？

它们通常是下载来的基础系统包，体积很大，属于依赖资源，不属于你自己写的代码。

---

### `rk3588-linux/debian/*.tar.xz`

例如：

```text
linaro-bookworm-xfce-arm64.tar.xz
linaro-bullseye-xfce-arm64.tar.xz
```

这是 Debian / Linaro 根文件系统压缩包。

### 为什么屏蔽？

理由同上：体积大、可下载、可重新生成，不适合放进 GitHub。

---

## 2. Kernel 编译产物

```gitignore
rk3588-linux/kernel/vmlinux
rk3588-linux/kernel/vmlinux.o
rk3588-linux/kernel/*.o
rk3588-linux/kernel/*.ko
rk3588-linux/kernel/*.a
```

### `rk3588-linux/kernel/vmlinux`

这是 Linux 内核编译出来的未压缩内核 ELF 文件。

你之前查到它大约 500MB：

```text
523855504 ./rk3588-linux/kernel/vmlinux
```

### 为什么屏蔽？

它是编译结果，不是源码。  
源码仓库中应提交内核源码和配置，而不是编译后的内核文件。

---

### `rk3588-linux/kernel/vmlinux.o`

这是链接 Linux 内核时产生的巨大目标文件。

你之前查到它大约 1.2GB：

```text
1274021792 ./rk3588-linux/kernel/vmlinux.o
```

### 为什么屏蔽？

这是典型的编译中间产物，体积极大，而且可以重新编译生成。

---

### `rk3588-linux/kernel/*.o`

`.o` 是 C/C++ 编译后的目标文件。

### 为什么屏蔽？

`.o` 文件是源码编译生成的中间文件。  
只需要提交 `.c`、`.h`、`Makefile`、配置文件等源码内容。

---

### `rk3588-linux/kernel/*.ko`

`.ko` 是 Linux 内核模块文件，例如：

```text
wifi.ko
camera.ko
```

### 为什么屏蔽？

它是内核模块编译结果。一般不提交到源码仓库，除非你明确要发布二进制驱动。

---

### `rk3588-linux/kernel/*.a`

`.a` 是静态库文件。

### 为什么屏蔽？

通常也是编译产物，可以重新生成。

---

## 3. Buildroot 下载缓存和输出目录

```gitignore
rk3588-linux/buildroot/dl/
rk3588-linux/buildroot/output/
```

### `rk3588-linux/buildroot/dl/`

Buildroot 的下载缓存目录，里面有各种源码压缩包、Git 下载缓存。

你之前看到里面有：

```text
qtwebengine-chromium-xxx.tar.bz2
qemu-6.1.0.tar.xz
rust-1.54.0-x86_64-unknown-linux-gnu.tar.xz
```

### 为什么屏蔽？

这是第三方依赖下载缓存，非常大，不是你的源码。  
别人重新构建时可以由 Buildroot 再下载。

---

### `rk3588-linux/buildroot/output/`

Buildroot 的编译输出目录。

里面通常有：

```text
images/
build/
target/
host/
staging/
```

### 为什么屏蔽？

这是 Buildroot 构建生成物，不该进 Git。

---

## 4. 通用构建输出

```gitignore
rk3588-linux/output/
rk3588-linux/build/
rk3588-linux/.repo/
```

### `rk3588-linux/output/`

Rockchip SDK 通常会把最终镜像、固件、打包结果放到 `output/`。

### 为什么屏蔽？

这是最终编译输出，不是源码。

---

### `rk3588-linux/build/`

通用构建目录，可能存放中间文件。

### 为什么屏蔽？

它通常由编译过程生成，可以重新生成。

---

### `rk3588-linux/.repo/`

如果这个 RK3588 SDK 是通过 `repo` 工具拉下来的，`.repo/` 是 repo 工具的管理目录。

它里面可能包括：

```text
manifest
project list
repo metadata
git objects
```

### 为什么屏蔽？

`.repo/` 是下载管理工具的内部目录，不应该提交到自己的 GitHub 仓库。  
如果要记录 SDK 来源，建议提交 manifest 或 README，而不是整个 `.repo/`。

---

## 5. 大型镜像 / 压缩包 / 安装包

```gitignore
*.img
*.iso
*.bin
*.tar
*.tar.gz
*.tgz
*.tar.xz
*.zip
*.7z
*.rar
*.deb
*.rpm
*.bz2
```

这一组是按文件后缀屏蔽。

### `*.img`

系统镜像、rootfs 镜像、固件镜像。

### 为什么屏蔽？

通常体积很大，是最终产物，不适合提交到普通 Git 仓库。

---

### `*.iso`

光盘镜像。

### 为什么屏蔽？

大文件，不适合进 Git。

---

### `*.bin`

二进制固件或裸二进制文件。

### 为什么屏蔽？

一般不是源码，且可能很大。

注意：有些嵌入式项目确实需要提交小的固件 `.bin`。如果你有必须保留的，可以单独取消忽略。

---

### `*.tar` / `*.tar.gz` / `*.tgz` / `*.tar.xz` / `*.bz2`

各种压缩包。

### 为什么屏蔽？

通常是下载包、备份包、源码包、rootfs 包，不建议进 Git。

---

### `*.zip` / `*.7z` / `*.rar`

压缩包。

### 为什么屏蔽？

通常是外部资源或打包结果，不适合源码管理。

---

### `*.deb` / `*.rpm`

Linux 安装包。

### 为什么屏蔽？

这是系统软件包，不是源码。别人可以通过包管理器或构建脚本获取。

---

## 6. 编译产物

```gitignore
*.o
*.ko
*.a
*.so
*.dtb
*.dtbo
```

### `*.o`

目标文件。

### 为什么屏蔽？

C/C++ 编译中间产物，不需要提交。

---

### `*.ko`

Linux 内核模块。

### 为什么屏蔽？

内核模块编译结果，不是源码。

---

### `*.a`

静态库。

### 为什么屏蔽？

编译产物，一般可以重新生成。

---

### `*.so`

动态库。

### 为什么屏蔽？

通常是编译产物或第三方二进制库。

注意：如果某些 `.so` 是 SDK 必须带的闭源库，那要谨慎。  
如果你确定项目运行必须依赖某些 `.so`，可以单独放行。

---

### `*.dtb`

Device Tree Blob，设备树编译后的二进制文件。

### 为什么屏蔽？

它是 `.dts` / `.dtsi` 编译后的结果。一般提交设备树源码，不提交 `.dtb`。

---

### `*.dtbo`

Device Tree Overlay 编译结果。

### 为什么屏蔽？

同样是编译产物。

---

## 7. 日志、缓存、临时目录

```gitignore
*.log
tmp/
.cache/
```

### `*.log`

日志文件。

### 为什么屏蔽？

日志是运行或编译时产生的临时信息，不适合提交。

---

### `tmp/`

临时目录。

### 为什么屏蔽？

临时文件没有长期维护价值。

---

### `.cache/`

缓存目录。

### 为什么屏蔽？

缓存可重新生成，不应进入 Git。

---

## 8. 临时工具生成目录

```gitignore
rk3588-linux/.codex_tmp_pymupdf/
```

### 作用

这个看起来像是某个工具临时生成的 PyMuPDF 相关目录。

你之前暂存区里出现过：

```text
rk3588-linux/.codex_tmp_pymupdf/pymupdf/mupdfcpp64.dll
rk3588-linux/.codex_tmp_pymupdf/pymupdf/_mupdf.pyd
```

### 为什么屏蔽？

这是临时工具目录，不是 RK3588 SDK 源码的一部分。  
而且里面有 `.dll`、`.pyd` 这种二进制文件。

---

## 9. 预编译工具链

```gitignore
rk3588-linux/prebuilts/
```

### 作用

`prebuilts/` 通常存放预编译好的交叉编译工具链，例如：

```text
gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
```

你之前看到里面有：

```text
cc1plus
f951
cc1
lto1
gdb
libstdc++.so
```

### 为什么屏蔽？

工具链非常大，而且是第三方预编译包。  
GitHub 仓库一般不直接放完整工具链，而是在 README 里说明如何下载或安装。

---

## 10. Windows 工具 / Linux 二进制工具

```gitignore
rk3588-linux/tools/windows/
rk3588-linux/tools/linux/PinDebug/
rk3588-linux/tools/linux/rk_sign_tool/bin/
```

### `rk3588-linux/tools/windows/`

Windows 下的烧录工具、调试工具等。

你之前看到：

```text
Rockchip_USB_SQ_Tool_V1.5.exe
```

### 为什么屏蔽？

`.exe` 是 Windows 可执行文件，体积较大，不是源码。

---

### `rk3588-linux/tools/linux/PinDebug/`

Rockchip 或板厂提供的 pin 调试工具。

你之前看到：

```text
pin_debug_tool_v1.11_for_linux.tar
```

### 为什么屏蔽？

这是工具包，不是源码，通常可以从 SDK 或厂商资料重新获取。

---

### `rk3588-linux/tools/linux/rk_sign_tool/bin/`

签名工具的二进制目录。

### 为什么屏蔽？

里面是可执行文件，如：

```text
boot_merger
afptool
update_image_maker
```

这些是二进制工具，不是你写的源码。

---

## 11. 大型媒体 / 二进制文件后缀

```gitignore
*.exe
*.dll
*.pyd
*.wav
*.ttf
```

### `*.exe`

Windows 可执行程序。

### 为什么屏蔽？

二进制工具，不适合进源码仓库。

---

### `*.dll`

Windows 动态库。

### 为什么屏蔽？

二进制依赖或工具库，不是源码。

---

### `*.pyd`

Python 在 Windows 下的扩展模块，本质上是二进制库。

### 为什么屏蔽？

不是源码。

---

### `*.wav`

音频文件。

你之前看到过：

```text
test_16k_1a1.wav
test_16k_2mic_cmd.wav
```

### 为什么屏蔽？

测试音频通常比较大，不属于核心源码。  
如果项目确实需要这些测试样本，可以单独保留。

---

### `*.ttf`

字体文件。

你之前看到过：

```text
msyh.ttf
```

### 为什么屏蔽？

字体可能较大，也可能涉及授权问题。一般不建议随便提交。

---

## 12. Demo 里的运行时动态库

```gitignore
rk3588-linux/external/camera_engine_rkaiq/rkisp_demo/demo/iio/lib/
```

### 作用

这个目录看起来是 RKAIQ / ISP demo 运行时依赖库，里面有：

```text
libc.so.6
libstdc++.so.6
libgcc_s.so.1
libm.so.6
```

### 为什么屏蔽？

这些是 demo 带的运行时库，属于二进制库，不是源码。  
而且你的暂存区里这些库都比较大。

---

## 13. 板级工具二进制

```gitignore
rk3588-linux/device/rockchip/common/tools/
rk3588-linux/device/rockchip/common/data/tools/
rk3588-linux/tools/linux/Linux_SecurityAVB/scripts/fastboot
rk3588-linux/tools/linux/rk_sign_tool/
rk3588-linux/rkbin/tools/
```

### `rk3588-linux/device/rockchip/common/tools/`

Rockchip 设备相关工具。

你之前看到：

```text
gdb
```

### 为什么屏蔽？

这是工具二进制，不是源码。

---

### `rk3588-linux/device/rockchip/common/data/tools/`

设备相关数据工具目录。

你之前看到：

```text
gdb_aarch64
gdb_armhf
```

### 为什么屏蔽？

二进制调试工具，体积大，可从 SDK 获取。

---

### `rk3588-linux/tools/linux/Linux_SecurityAVB/scripts/fastboot`

`fastboot` 工具。

### 为什么屏蔽？

这是 Android / AVB 相关烧录工具二进制，不是源码。

---

### `rk3588-linux/tools/linux/rk_sign_tool/`

Rockchip 签名工具目录。

### 为什么屏蔽？

它主要用于打包、签名、合成镜像，里面很多二进制工具。

---

### `rk3588-linux/rkbin/tools/`

`rkbin` 里的 Rockchip 工具目录。

你之前看到：

```text
rk_sign_tool
upgrade_tool
```

### 为什么屏蔽？

这也是二进制工具目录。  
不过注意：`rkbin` 里面有些文件可能是 Rockchip 固件、loader、ddr bin 等。如果项目需要完整 SDK 构建，通常不要随便忽略整个 `rkbin/`，这里只忽略 `rkbin/tools/`。

---

## 14. 示例媒体、游戏、OEM demo 文件

```gitignore
rk3588-linux/device/rockchip/common/images/oem/
rk3588-linux/buildroot/board/rockchip/rk3588/fs-overlay/oem/
*.mp4
*.gba
```

### `rk3588-linux/device/rockchip/common/images/oem/`

OEM 示例资源目录。

你之前看到：

```text
game_test.gba
SampleVideo_1280x720_5mb.mp4
```

### 为什么屏蔽？

这些是示例视频、游戏、资源文件，不是核心源码。

---

### `rk3588-linux/buildroot/board/rockchip/rk3588/fs-overlay/oem/`

Buildroot rootfs overlay 里的 OEM 示例资源。

### 为什么屏蔽？

这里面也有 demo 视频、游戏、测试资源。  
如果你的产品真的需要某些 OEM 资源，可以单独放行。

---

### `*.mp4`

视频文件。

### 为什么屏蔽？

媒体文件容易变大，不适合 Git。

---

### `*.gba`

Game Boy Advance ROM 文件。

### 为什么屏蔽？

这是示例游戏文件，不属于源码，也可能有版权问题。

---

## 15. PDF 文档

```gitignore
*.pdf
```

### 作用

屏蔽 PDF 文档，例如：

```text
Rockchip_Quick_Start_RKNN_SDK_V1.5.0_CN.pdf
Rockchip_Developer_Guide_MPI_CN.pdf
```

### 为什么屏蔽？

PDF 文档通常比较大，而且是厂商资料，不是代码。

不过这一条要看你的需求：

- 如果你希望 GitHub 仓库里保留文档，可以删掉 `*.pdf`
- 如果你只是为了把源码推上去，屏蔽 PDF 是合理的

---

# 强烈建议保留的屏蔽项

这些基本都是大文件、生成文件、缓存、编译产物，建议一定屏蔽：

```gitignore
rk3588-linux/ubuntu/binary/
rk3588-linux/ubuntu/rootfs.img
rk3588-linux/ubuntu/*.tar.xz
rk3588-linux/debian/*.tar.xz
rk3588-linux/buildroot/dl/
rk3588-linux/buildroot/output/
rk3588-linux/output/
rk3588-linux/build/
rk3588-linux/prebuilts/
rk3588-linux/kernel/vmlinux
rk3588-linux/kernel/vmlinux.o
*.img
*.tar.xz
*.o
*.ko
```

---

# 需要谨慎屏蔽的项

这些需要根据你的项目实际情况判断：

```gitignore
*.so
*.bin
*.pdf
rk3588-linux/rkbin/tools/
rk3588-linux/device/rockchip/common/images/oem/
```

原因：

- `*.so`：有些闭源动态库可能是运行必须的。
- `*.bin`：有些固件可能必须保留。
- `*.pdf`：如果你希望仓库带文档，就不要屏蔽。
- `rkbin/tools/`：一般可以屏蔽，但不要误屏蔽重要 loader / firmware。
- `images/oem/`：如果里面有你产品自己的 UI 资源，就不要整目录屏蔽。

---

# 如果某个被屏蔽的文件你想强制提交

例如你想保留某个 PDF：

```bash
git add -f rk3588-linux/external/rknpu2/doc/Rockchip_Quick_Start_RKNN_SDK_V1.5.0_CN.pdf
```

或者在 `.gitignore` 最下面写例外规则：

```gitignore
!rk3588-linux/external/rknpu2/doc/Rockchip_Quick_Start_RKNN_SDK_V1.5.0_CN.pdf
```

---

# 推荐的提交检查命令

检查暂存区总大小：

```bash
git diff --cached --name-only -z | xargs -0 du -b 2>/dev/null | awk '{sum+=$1} END {printf "%.2f GB\n", sum/1024/1024/1024}'
```

检查暂存区最大的 30 个文件：

```bash
git diff --cached --name-only -z | xargs -0 du -b 2>/dev/null | sort -nr | head -30
```

如果总大小低于 1GB 左右，并且没有单个超大文件，通常可以提交：

```bash
git commit -m "Initial commit"
git push -u origin main
```

---

# 总结

这份 `.gitignore` 的核心目标是：

1. 避免把 rootfs、镜像、工具链、缓存、编译输出提交到 GitHub。
2. 避免 GitHub push 失败。
3. 保持仓库轻量，方便别人 clone。
4. 让仓库主要保存真正有维护价值的源码、配置、脚本和说明文档。

一句话总结：

> GitHub 里放源码、配置、脚本、补丁；不要放 rootfs、镜像、工具链、缓存、编译输出、大型二进制文件。
