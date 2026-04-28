#!/bin/bash -e
# build_buildroot 编译buildroot
# build_debian11 编译debian11
# build_debian12 编译debian12
# build_ubuntu20 编译ubuntu20
# build_ubuntu22 编译ubuntu22
# usage_hook 打印帮助选项
# clean_hook 清理编译内容
# init_hook 编译前的初始化函数
# pre_build_hook 编译buildroot前的一些其他配置，例如修改默认配置文件
# build_hook 文件系统编译的钩子函数

# 编译buildroot
build_buildroot()
{
	check_config RK_BUILDROOT_CFG || return 0

	ROOTFS_DIR="${1:-$RK_OUTDIR/buildroot}"

	/usr/bin/time -f "you take %E to build buildroot" \
		"$SCRIPTS_DIR/mk-buildroot.sh" $RK_BUILDROOT_CFG "$ROOTFS_DIR"

	cat "$RK_LOG_DIR/post-rootfs.log"
	finish_build build_buildroot $@
}

# 编译debian11
build_debian11()
{
	ROOTFS_DIR="${1:-$RK_OUTDIR/debian}"
    cd debian
    VERSION=debian11 ./mk-rootfs.sh
	./mk-image.sh

	ln -rsf "$PWD/rootfs.img" $ROOTFS_DIR/rootfs.ext4
	finish_build build_debian11 $@
}

# 编译debian12 
build_debian12()
{
	ROOTFS_DIR="${1:-$RK_OUTDIR/debian}"
    cd debian
    VERSION=debian12 ./mk-rootfs.sh
	./mk-image.sh

	ln -rsf "$PWD/rootfs.img" $ROOTFS_DIR/rootfs.ext4
	finish_build build_debian12 $@
}

# ubuntu20编译函数
build_ubuntu20()
{
    ROOTFS_DIR="${1:-$RK_OUTDIR/ubuntu}"
    cd ubuntu
    VERSION=ubuntu20 ./mk-rootfs.sh
	./mk-image.sh

	ln -rsf "$PWD/rootfs.img" $ROOTFS_DIR/rootfs.ext4
	finish_build build_ubuntu20 $@
}

# ubuntu22编译函数
build_ubuntu22()
{
    ROOTFS_DIR="${1:-$RK_OUTDIR/ubuntu}"
    cd ubuntu
    VERSION=ubuntu22 ./mk-rootfs.sh
	./mk-image.sh

	ln -rsf "$PWD/rootfs.img" $ROOTFS_DIR/rootfs.ext4
	finish_build build_ubuntu22 $@
}

# 打印帮助选项
usage_hook()
{
	#echo -e "buildroot-config[:<config>]       \tmodify buildroot defconfig"
	#echo -e "buildroot-make[:<arg1>:<arg2>]    \trun buildroot make"
	echo -e "rootfs[:<rootfs type>]            \tbuild default rootfs"
	echo -e "buildroot                         \tbuild buildroot rootfs"
	echo -e "debian11                            \tbuild debian11 rootfs"
	echo -e "debian12                            \tbuild debian12 rootfs"
	echo -e "ubuntu20                            \tbuild ubuntu20 rootfs"
	echo -e "ubuntu22                            \tbuild ubuntu22 rootfs"
}

# 清理编译内容
clean_hook()
{
	sudo rm -rf debian/binary
	sudo rm -rf ubuntu/binary
	sudo rm -rf ubuntu/rootfs.img
	sudo rm -rf debian/rootfs.img
	if check_config RK_BUILDROOT_CFG &>/dev/null; then
		rm -rf buildroot/output/$RK_BUILDROOT_CFG
	fi

	rm -rf "$RK_OUTDIR/buildroot"
	rm -rf "$RK_OUTDIR/debian"
	rm -rf "$RK_OUTDIR/ubuntu"
	rm -rf "$RK_OUTDIR/rootfs"
	rm -rf "$SDK_DIR/script_run_flag"
}

INIT_CMDS="default buildroot debian11 debian12 ubuntu20 ubuntu22"

# 编译前的初始化函数
init_hook()
{
	load_config RK_ROOTFS_TYPE
	check_config RK_ROOTFS_TYPE &>/dev/null || return 0

	# Priority: cmdline > custom env
	if [ "$1" != default ]; then
		export RK_ROOTFS_SYSTEM=$1
		echo "Using rootfs system($RK_ROOTFS_SYSTEM) from cmdline"
	elif [ "$RK_ROOTFS_SYSTEM" ]; then
		export RK_ROOTFS_SYSTEM=${RK_ROOTFS_SYSTEM//\"/}
		echo "Using rootfs system($RK_ROOTFS_SYSTEM) from environment"
	else
		return 0
	fi

	ROOTFS_CONFIG="RK_ROOTFS_SYSTEM=\"$RK_ROOTFS_SYSTEM\""
	ROOTFS_UPPER=$(echo $RK_ROOTFS_SYSTEM | tr 'a-z' 'A-Z')
	ROOTFS_CHOICE="RK_ROOTFS_SYSTEM_$ROOTFS_UPPER"
	if ! grep -q "^$ROOTFS_CONFIG$" "$RK_CONFIG"; then
		if ! grep -wq "$ROOTFS_CHOICE" "$RK_CONFIG"; then
			echo -e "\e[35m$RK_ROOTFS_SYSTEM not supported!\e[0m"
			return 0
		fi

		sed -i -e "/RK_ROOTFS_SYSTEM/d" "$RK_CONFIG"
		echo "$ROOTFS_CONFIG" >> "$RK_CONFIG"
		echo "$ROOTFS_CHOICE=y" >> "$RK_CONFIG"
		"$SCRIPTS_DIR/mk-config.sh" olddefconfig &>/dev/null
	fi
}

PRE_BUILD_CMDS="buildroot-config buildroot-make bmake"

# 编译buildroot前的一些其他配置，例如修改默认配置文件
pre_build_hook()
{
	check_config RK_ROOTFS_TYPE || return 0

	case "$1" in
		buildroot-make | bmake)
			check_config RK_BUILDROOT_CFG || return 0

			shift
			"$SCRIPTS_DIR/mk-buildroot.sh" $RK_BUILDROOT_CFG make $@
			finish_build buildroot-make $@
			;;
		buildroot-config)
			BUILDROOT_BOARD="${2:-"$RK_BUILDROOT_CFG"}"

			[ "$BUILDROOT_BOARD" ] || return 0

			TEMP_DIR=$(mktemp -d)
			"$SDK_DIR/buildroot/build/parse_defconfig.sh" \
				"$BUILDROOT_BOARD" "$TEMP_DIR/.config"
			make -C "$SDK_DIR/buildroot" O="$TEMP_DIR" menuconfig
			"$SDK_DIR/buildroot/build/update_defconfig.sh" \
				"$BUILDROOT_BOARD" "$TEMP_DIR"

			finish_build $@
			;;
	esac
}

BUILD_CMDS="rootfs buildroot debian11 debian12 ubuntu20 ubuntu22"

# 文件系统编译的钩子函数
build_hook()
{
	check_config RK_ROOTFS_TYPE || return 0

	if [ -z "$1" -o "$1" = rootfs ]; then
		ROOTFS=${RK_ROOTFS_SYSTEM:-buildroot}
	else
		ROOTFS=$1
	fi

	ROOTFS_IMG=rootfs.${RK_ROOTFS_TYPE}
	ROOTFS_DIR="$RK_OUTDIR/rootfs"

	echo "=========================================="
	echo "          Start building rootfs($ROOTFS)"
	echo "=========================================="

	rm -rf "$ROOTFS_DIR"
	mkdir -p "$ROOTFS_DIR"

	case "$ROOTFS" in
		debian11) build_debian11 "$ROOTFS_DIR" ;;
		debian12) build_debian12 "$ROOTFS_DIR" ;;
		ubuntu20) build_ubuntu20 "$ROOTFS_DIR" ;;
		ubuntu22) build_ubuntu22 "$ROOTFS_DIR" ;;
		buildroot) build_buildroot "$ROOTFS_DIR" ;;
		*) usage ;;
	esac

	if [ ! -f "$ROOTFS_DIR/$ROOTFS_IMG" ]; then
		echo "There's no $ROOTFS_IMG generated..."
		exit 1
	fi

	ln -rsf "$ROOTFS_DIR/$ROOTFS_IMG" "$RK_FIRMWARE_DIR/rootfs.img"

	# For builtin OEM image
	[ ! -e "$ROOTFS_DIR/oem.img" ] || \
		ln -rsf "$ROOTFS_DIR/oem.img" "$RK_FIRMWARE_DIR"

	if [ "$RK_ROOTFS_INITRD" ]; then
		/usr/bin/time -f "you take %E to pack ramboot image" \
			"$SCRIPTS_DIR/mk-ramdisk.sh" \
			"$RK_FIRMWARE_DIR/rootfs.img" \
			"$ROOTFS_DIR/ramboot.img" "$RK_BOOT_FIT_ITS"
		ln -rsf "$ROOTFS_DIR/ramboot.img" \
			"$RK_FIRMWARE_DIR/boot.img"

		# For security
		cp "$RK_FIRMWARE_DIR/boot.img" u-boot/
	fi

	if [ "$RK_SECURITY" ]; then
		echo "Try to build init for $RK_SECURITY_CHECK_METHOD"

		if [ "$RK_SECURITY_CHECK_METHOD" = "DM-V" ]; then
			SYSTEM_IMG=rootfs.squashfs
		else
			SYSTEM_IMG=$ROOTFS_IMG
		fi
		if [ ! -f "$ROOTFS_DIR/$SYSTEM_IMG" ]; then
			echo "There's no $SYSTEM_IMG generated..."
			exit -1
		fi

		"$SCRIPTS_DIR/mk-dm.sh" $RK_SECURITY_CHECK_METHOD \
			"$ROOTFS_DIR/$SYSTEM_IMG"
		ln -rsf "$ROOTFS_DIR/security-system.img" \
			"$RK_FIRMWARE_DIR/rootfs.img"
	fi

	finish_build build_rootfs $@
}

source "${BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

case "${1:-rootfs}" in
	buildroot-config | buildroot-make | bmake) pre_build_hook $@ ;;
	buildroot | debian | yocto) init_hook $@ ;&
	*) build_hook $@ ;;
esac
