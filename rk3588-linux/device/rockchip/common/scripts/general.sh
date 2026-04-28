#!/bin/bash
# 存放通用函数，使build.sh看起来整洁

# usage() 帮助信息打印函数
# err_handler() 错误处理函数
# install_package() 安装编译需要的软件包
# set_python() 设置Python版本
# set_swapfile() 设置交换分区
# finish_build() 脚本执行完成打印函数
# load_config() config配置文件加载函数
# check_config() 检查配置文件
# kernel_version_real() 内核版本获取函数
# kernel_version() 内核版本获取函数
# start_log() 打印日志信息设置
# rroot() 进入到根目录
# rout() 进入到ountut目录
# rcommon() 进入common目录
# rscript() 进入script脚本存放目录
# rchip() 进入板级配置目录
# run_hooks() 钩子脚本运行函数
# run_build_hooks() 编译钩子脚本运行函数
# run_post_hooks() 后处理钩子运行函数
# option_check() 参数检查函数
# set_log() 打印日志设置函数
# print_env() 环境变量打印函数


# 设置一些环境变量
export LC_ALL=C # 设置本地化环境为C

export SCRIPTS_DIR="$(dirname "$(realpath "$BASH_SOURCE")")" # build.sh脚本路径
export COMMON_DIR="$(realpath "$SCRIPTS_DIR/..")" # common目录路径
export SDK_DIR="$(realpath "$COMMON_DIR/../../..")" # SDK源码根目录路径
export DEVICE_DIR="$SDK_DIR/device/rockchip" # 脚本和板级别配置文件路径
export CHIPS_DIR="$DEVICE_DIR/.chips"  # .chips路径,里面其实也只有一个rk3562
export CHIP_DIR="$DEVICE_DIR/.chip" # .chip路径也就是rk3562

export RK_DATA_DIR="$COMMON_DIR/data" # 存放了一些调试工具和开发板可执行脚本
export RK_IMAGE_DIR="$COMMON_DIR/images" # 存放了ome userdata PCBA等镜像或者分区文件
export RK_CONFIG_IN="$COMMON_DIR/configs/Config.in" # 存放了一些配置文件，推测根目录的menuconfig就是来自这里

export RK_BUILD_HOOK_DIR="$COMMON_DIR/build-hooks" # 存放编译钩子脚本的目录
export BUILD_HELPER="$RK_BUILD_HOOK_DIR/build-helper" # 编译时钩子的帮助函数
export RK_POST_HOOK_DIR="$COMMON_DIR/post-hooks" # 存放编译完成后的钩子脚本目录
export POST_HELPER="$RK_POST_HOOK_DIR/post-helper" # 编译完成后的钩子帮助函数

export PARTITION_HELPER="$SCRIPTS_DIR/partition-helper" # 文件分区函数

export RK_OUTDIR="$SDK_DIR/output" # 文件输出保存目录
export RK_LOG_BASE_DIR="$RK_OUTDIR/log"	#log日志保存总目录
export RK_SESSION="${RK_SESSION:-$(date +%F_%H-%M-%S)}" #日志时间定义
export RK_LOG_DIR="$RK_LOG_BASE_DIR/$RK_SESSION" # 根据时间保存的日志目录
export RK_FIRMWARE_DIR="$RK_OUTDIR/firmware" # 固件存放目录
export RK_INITIAL_ENV="$RK_OUTDIR/initial.env" # 保存的最初环境
export RK_CUSTOM_ENV="$RK_OUTDIR/custom.env" 
export RK_FINAL_ENV="$RK_OUTDIR/final.env"	#最终的环境变量
export RK_CONFIG="$RK_OUTDIR/.config" # 保存的Menuconfig配置
export RK_DEFCONFIG_LINK="$RK_OUTDIR/defconfig"  # 默认配置

export PYTHON3=/usr/bin/python3 # 导出环境变量 PYTHON3，指定为 /usr/bin/python3
export CPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1) # 获取最大CPU核心数

# 强制导出配置环境变量
set -a

# usage() 帮助信息打印函数
usage()
{
	echo "Usage: $(basename $BASH_SOURCE) [OPTIONS]"
	echo "Available options:"

	run_build_hooks usage

	# Global options
	echo -e "cleanall                          \tcleanup"
	echo -e "post-rootfs <rootfs dir>          \ttrigger post-rootfs hook scripts"
	echo -e "shell                             \tsetup a shell for developing"
	echo -e "help                              \tusage"
	echo ""
	echo "Default option is 'allsave'."
	exit 0
}

# 错误处理函数
err_handler()
{
	ret=${1:-$?} # 获取错误码，如果未提供参数，则使用上一个命令的退出状态码
	[ "$ret" -eq 0 ] && return # 如果错误码为零，表示没有错误，直接返回

	echo "ERROR: Running $BASH_SOURCE - ${2:-${FUNCNAME[1]}} failed!" # 输出错误信息，包括脚本文件路径和失败的函数或命令名称
	echo "ERROR: exit code $ret from line ${BASH_LINENO[0]}:" # 输出错误码和导致错误的行号
	echo "    ${3:-$BASH_COMMAND}" # 输出导致错误的命令或函数调用

	echo "ERROR: call stack:" # 输出调用堆栈信息，即函数调用的层次关系
	for i in $(seq 1 $((${#FUNCNAME[@]} - 1))); do # 遍历函数调用堆栈
		SOURCE="${BASH_SOURCE[$i]}" # 获取调用的脚本文件路径
		LINE=${BASH_LINENO[$(( $i - 1 ))]} # 获取调用发生的行号
		echo "    $(basename "$SOURCE"): ${FUNCNAME[$i]}($LINE)" # 输出调用的脚本文件名、函数名称和行号
	done

	exit $ret # 退出脚本，并返回错误码
}

# 安装编译所需的依赖包
install_package() {
    # 检查网络连接
    HOSTRELEASE=$(grep VERSION_CODENAME /etc/os-release | cut -d"=" -f2)
    echo -e "\e[33m当前运行的系统为 $HOSTRELEASE.\e[0m"
    echo -e "\e[34m正在检查网络连接...\e[0m"
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "\e[32m网络连接正常，开始安装依赖包。\e[0m"

        # 通用必需依赖包列表，适用于内核、Buildroot、U-Boot、设备树等
        COMMON_PACKAGES=(
            whiptail dialog psmisc acl uuid uuid-runtime curl gpg gnupg gawk git
            aptly aria2 bc binfmt-support bison btrfs-progs build-essential
            ca-certificates ccache cpio cryptsetup debian-archive-keyring
            debian-keyring debootstrap device-tree-compiler dirmngr dosfstools
            dwarves f2fs-tools fakeroot flex gcc-arm-linux-gnueabihf gdisk imagemagick
            jq kmod libbison-dev libc6-dev-armhf-cross libelf-dev libfdt-dev
            libfile-fcntllock-perl libfl-dev liblz4-tool libncurses-dev libssl-dev
            libusb-1.0-0-dev linux-base locales lzop ncurses-base ncurses-term
            nfs-kernel-server ntpdate p7zip-full parted patchutils pigz pixz pkg-config
            pv python3-dev qemu-user-static rsync swig systemd-container u-boot-tools
            udev unzip uuid-dev wget zip zlib1g-dev distcc lib32ncurses-dev
            lib32stdc++6 libc6-i386 python3 expect expect-dev cmake vim openssh-server
            net-tools texinfo htop
        )

        # Ubuntu 18.04 特定的依赖包
        UBUNTU_18_PACKAGES=(
            liblz-dev liblzo2-2 liblzo2-dev mtd-utils squashfs-tools schedtool
            g++-multilib lib32z1-dev lib32ncurses5-dev lib32readline-dev gcc-multilib
            patchelf chrpath texinfo diffstat python3-pip subversion sed binutils
            bzip2 patch gzip perl tar file bc tcl android-tools-fsutils openjdk-8-jdk
            libsdl1.2-dev libesd-java libwxgtk3.0-dev repo bzr cvs mercurial pngcrush xsltproc
            gperf libc6-dev
        )

        # Ubuntu 20.04 和 22.04 特定的依赖包
        UBUNTU_20_22_PACKAGES=(
            python2 python3-distutils libpython2.7-dev
        )

        if [ "$HOSTRELEASE" == "bionic" ]; then
            echo -e "\e[33m正在安装 Ubuntu 18.04 编译所需依赖包...\e[0m"
            sudo apt-get update
            sudo apt-get -y upgrade
            sudo apt-get install -y --no-install-recommends "${COMMON_PACKAGES[@]}" "${UBUNTU_18_PACKAGES[@]}"
            echo -e "\e[32m依赖包安装完成。\e[0m"
        elif [ "$HOSTRELEASE" == "focal" ] || [ "$HOSTRELEASE" == "jammy" ]; then
            echo -e "\e[33m正在安装 Ubuntu 20.04 / 22.04 编译所需依赖包...\e[0m"
            sudo apt-get update
            sudo apt-get -y upgrade
            sudo apt-get install -y --no-install-recommends "${COMMON_PACKAGES[@]}" "${UBUNTU_20_22_PACKAGES[@]}"
            echo -e "\e[32m依赖包安装完成。\e[0m"
        elif [ "$HOSTRELEASE" == "noble" ]; then
            echo -e "\e[33m正在安装 Ubuntu 24.04 编译所需依赖包...\e[0m"
            sudo apt-get update
            sudo apt-get -y upgrade
            sudo apt-get install -y --no-install-recommends "${COMMON_PACKAGES[@]}"
            echo -e "\e[32m依赖包安装完成。\e[0m"
        else
            echo -e "\e[33m您的系统不是 Ubuntu 18.04 / 20.04 / 22.04 / 24.04，请自行安装依赖包。\e[0m"
        fi
    else
        # 没有网络连接，提示并退出函数
        echo -e "\e[31m未检测到网络连接，请确保已安装编译所需要的依赖包。\e[0m"
    fi
}


# 设置Python版本
set_python() {
    echo -e "\e[32m正在设置 Python 版本...\e[0m"
    if [ "$HOSTRELEASE" == "bionic" ] || [ "$HOSTRELEASE" == "focal" ] || [ "$HOSTRELEASE" == "jammy" ]; then
        sudo ln -fs /usr/bin/python2.7 /usr/bin/python
        sudo ln -fs /usr/bin/python2.7 /usr/bin/python2
        echo -e "\e[32mPython 版本已设置为 Python 2.7。\e[0m"
    elif [ "$HOSTRELEASE" == "noble" ]; then
        sudo ln -fs /usr/bin/python3 /usr/bin/python
        sudo ln -fs /usr/bin/python3 /usr/bin/python2
        echo -e "\e[32mPython 版本已设置为 Python 3。\e[0m"
    else
        echo -e "\e[33m未知系统版本，无法设置 Python 版本。\e[0m"
    fi
}


# 设置交换分区
set_swapfile() {
    echo -e "\e[32m设置交换分区.\e[0m"
    # 检查交换文件 /swapfile 是否存在
    if [ -f /swapfile ]; then
        # 检查交换文件大小是否小于 10 GB
        if [ $(du -m /swapfile | awk '{print $1}') -lt 10240 ]; then
            # 禁用交换分区
            sudo swapoff /swapfile
            sudo dd if=/dev/zero of=/swapfile bs=1M count=20480
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
        fi
    else
        # 创建 20 GB 大小的交换文件
        sudo dd if=/dev/zero of=/swapfile bs=1M count=20480
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
    fi
}

# 脚本执行完成打印函数
finish_build()
{
	echo -e "\e[35mRunning $(basename "${BASH_SOURCE[1]}") - ${@:-${FUNCNAME[1]}} succeeded.\e[0m"
	cd "$SDK_DIR"
}

# config配置文件加载函数
load_config()
{
	[ -r "$RK_CONFIG" ] || return 0

	for var in $@; do
		export $(grep "^$var=" "$RK_CONFIG" | \
			tr -d '"' || true) &>/dev/null
	done
}

# 检查配置文件
check_config()
{
	unset missing
	for var in $@; do
		eval [ \$$var ] && continue

		missing="$missing $var"
	done

	[ -z "$missing" ] && return 0

	echo "Skipping $(basename "${BASH_SOURCE[1]}") - ${FUNCNAME[1]} for missing configs: $missing."
	return 1
}

# 内核版本获取函数
kernel_version_real()
{
	[ -d kernel ] || return 0

	VERSION_KEYS="VERSION PATCHLEVEL"
	VERSION=""

	for k in $VERSION_KEYS; do
		v=$(grep "^$k = " kernel/Makefile | cut -d' ' -f3)
		VERSION=${VERSION:+${VERSION}.}$v
	done
	echo $VERSION
}

# 内核版本获取函数
kernel_version()
{
	[ -d kernel ] || return 0

	KERNEL_DIR="$(basename "$(realpath kernel)")"
	case "$KERNEL_DIR" in
		kernel-*)
			echo ${KERNEL_DIR#kernel-}
			return 0
			;;
	esac

	kernel_version_real
}

# 打印日志信息设置
start_log()
{
	LOG_FILE="$RK_LOG_DIR/${2:-$1_$(date +%F_%H-%M-%S)}.log"
	ln -rsf "$LOG_FILE" "$RK_LOG_DIR/$1.log"
	echo "# $(date +"%F %T")" >> "$LOG_FILE"
	echo "$LOG_FILE"
}

# 进入到根目录
rroot()
{
	cd "$SDK_DIR"
}

# 进入到ountut目录
rout()
{
	cd "$RK_OUTDIR"
}

# 进入common目录
rcommon()
{
	cd "$COMMON_DIR"
}

# 进入script脚本存放目录
rscript()
{
	cd "$SCRIPTS_DIR"
}

# 进入板级配置目录
rchip()
{
	cd "$(realpath "$CHIP_DIR")"
}

# 钩子脚本运行函数
run_hooks()
{
	DIR="$1" # 传入的目录路径
	shift

	for dir in "$CHIP_DIR/$(basename "$DIR")/" "$DIR"; do # 遍历两个目录："$CHIP_DIR/传入目录的基本名称/" 和 "$DIR"
		[ -d "$dir" ] || continue # 如果目录不存在，则跳过当前循环

		for hook in $(find "$dir" -maxdepth 1 -name "*.sh" | sort); do # 遍历目录中的以 ".sh" 结尾的脚本文件
			"$hook" $@ && continue # 执行脚本文件，并继续下一次循环
			HOOK_RET=$? # 存储脚本文件的退出状态码
			err_handler $HOOK_RET "${FUNCNAME[0]} $*" "$hook $*" # 调用错误处理函数，传递错误码和相关参数
			exit $HOOK_RET # 退出脚本并返回脚本文件的退出状态码
		done
	done
}

# 编译钩子脚本运行函数
run_build_hooks()
{
	# 不记录这些钩子的日志
	case "$1" in
		init | pre-build | make-* | usage | support-cmds)
			run_hooks "$RK_BUILD_HOOK_DIR" $@ || true
			return 0
			;;
	esac

	LOG_FILE="$(start_log "$1")"

	echo -e "# run hook: $@\n" >> "$LOG_FILE" # 添加钩子名称到日志文件
	run_hooks "$RK_BUILD_HOOK_DIR" $@ 2>&1 | tee -a "$LOG_FILE" # 运行钩子并将输出写入日志文件
	HOOK_RET=${PIPESTATUS[0]}
	if [ $HOOK_RET -ne 0 ]; then
		err_handler $HOOK_RET "${FUNCNAME[0]} $*" "$@" # 处理错误，并传递相关参数
		exit $HOOK_RET # 钩子执行出错，退出脚本并返回钩子的返回码
	fi
}

# 后处理钩子运行函数
run_post_hooks()
{
	# 将 post-rootfs 的输出日志文件路径保存到 LOG_FILE 变量中
	LOG_FILE="$(start_log post-rootfs)"

	# 将要执行的钩子名称以及参数作为注释写入日志文件
	echo -e "# run hook: $@\n" >> "$LOG_FILE"

	# 调用 run_hooks() 函数执行指定目录下的钩子脚本，并将输出同时追加写入日志文件和终端，并将标准错误输出重定向到标准输出
	run_hooks "$RK_POST_HOOK_DIR" $@ 2>&1 | tee -a "$LOG_FILE"

	# 获取钩子脚本的返回值，并保存到 HOOK_RET 变量中
	HOOK_RET=${PIPESTATUS[0]}

	# 如果钩子脚本的返回值不为 0，则调用 err_handler() 处理错误，并将函数名、参数传递给 err_handler()，然后退出程序
	if [ $HOOK_RET -ne 0 ]; then
		err_handler $HOOK_RET "${FUNCNAME[0]} $*" "$@"
		exit $HOOK_RET
	fi
}

# 参数检查函数
option_check()
{
	CMDS="$1"
	shift

	for opt in $@; do
		for cmd in $CMDS; do
			# NOTE: There might be patterns in commands
			echo "${opt%%:*}" | grep -q "^$cmd$" || continue
			return 0
		done
	done

	return 1
}

# 交叉编译工具链获取函数
get_toolchain()
{
	TOOLCHAIN_ARCH="${1/arm64/aarch64}"  # 将参数中的 'arm64' 替换为 'aarch64'，并赋值给 TOOLCHAIN_ARCH 变量
	MACHINE=$(uname -m)  # 获取当前机器的架构信息
	TOOLCHAIN_OS=none  # 否则设置 TOOLCHAIN_OS 变量为 none
	TOOLCHAIN_DIR="$(realpath prebuilts/gcc/*/$TOOLCHAIN_ARCH)"  # 根据 TOOLCHAIN_ARCH 变量的值构建 TOOLCHAIN_DIR 变量的路径
	GCC="$(find "$TOOLCHAIN_DIR" -name "*$TOOLCHAIN_OS*-gcc" | \
		head -n 1)"  # 在 TOOLCHAIN_DIR 目录下查找以 "$TOOLCHAIN_OS-gcc" 结尾的文件，并取第一个结果，赋值给 GCC 变量
	if [ ! -x "$GCC" ]; then  # 如果 GCC 变量不是可执行文件
		echo "No prebuilt GCC toolchain!"  # 输出错误信息
		exit 1  # 退出脚本，返回状态码 1
	fi

	echo "${GCC%gcc}"  # 输出 GCC 变量的值，并删除结尾的 'gcc' 部分
}

# 打印日志设置函数
set_log()
{
	# 日志文件设置
	if [ ! -d "$RK_LOG_DIR" ]; then
		mkdir -p "$RK_LOG_DIR"
		rm -rf "$RK_LOG_BASE_DIR/latest"
		ln -rsf "$RK_LOG_DIR" "$RK_LOG_BASE_DIR/latest"
		echo -e "\e[33mLog saved at $RK_LOG_DIR\e[0m"
		echo
	fi

	# 删除 $RK_LOG_BASE_DIR 目录下按时间排序的前 10 个文件或目录
	cd "$RK_LOG_BASE_DIR"
	rm -rf $(ls -t | sed '1,10d')
}

# 环境变量打印函数
print_env()
{
	# 保存最终的环境变量，将当前环境变量保存到文件 $RK_FINAL_ENV
	env > "$RK_FINAL_ENV"
	cp "$RK_FINAL_ENV" "$RK_LOG_DIR"

	# Log configs
	echo
	echo "=========================================="
	echo "          Final configs"
	echo "=========================================="
	env | grep -E "^RK_.*=.+" | grep -vE "PARTITION_[0-9]" | \
		grep -vE "=\"\"$|_DEFAULT=y" | \
		grep -vE "^RK_CONFIG|_BASE_CFG=|_LINK=|DIR=|_ENV=|_NAME=" | sort
	echo
}

set_toolchain()
{
	RK_UBOOT_ARCH=arm64
	# 设置kernel交叉编译器
	export RK_KERNEL_TOOLCHAIN="$(get_toolchain "$RK_KERNEL_ARCH")"

	# 设置uboot交叉编译器和KMAKE
	export KMAKE="make -C kernel/ -j$(( $CPUS + 1 )) \
		CROSS_COMPILE=$RK_KERNEL_TOOLCHAIN ARCH=$RK_KERNEL_ARCH"
	export RK_UBOOT_TOOLCHAIN="$(get_toolchain "$RK_UBOOT_ARCH")"
}
# 强制导出配置环境变量
set +a
