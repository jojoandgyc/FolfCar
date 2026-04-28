#!/bin/bash -e
# build_all 编译所有镜像并打包，需要设置RK_ROOTFS_SYSTEM变量，否则会默认编译buildroot
# build_buildroot 编译所有buildroot镜像并打包
# build_debian11_all 编译所有debian11镜像并打包
# build_debian12_all 编译所有debian12镜像并打包
# build_ubuntu20_all 编译所有ubuntu20镜像并打包
# build_ubuntu22_all 编译所有ubuntu22镜像并打包
# build_save 编译完成后的后处理函数
# build_allsave 编译所有并进行后处理
# usage_hook打印帮助信息
# build_hook 编译全部镜像的钩子函数



BOARD=$(echo ${RK_KERNEL_DTS_NAME:-$(echo "$RK_DEFCONFIG" | \
	sed -n "s/.*\($RK_CHIP.*\)_defconfig/\1/p")} | \
	tr '[:lower:]' '[:upper:]')

#编译所有镜像并打包，需要设置RK_ROOTFS_SYSTEM变量，否则会默认编译buildroot
build_all()
{
	echo "=========================================="
	echo "          Start building buildroot all images"
	echo "=========================================="
	rm -rf $RK_FIRMWARE_DIR
	mkdir -p $RK_FIRMWARE_DIR

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ -z "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-security.sh" security_check

	if [ "$RK_KERNEL_CFG" ]; then
		"$SCRIPTS_DIR/mk-kernel.sh"
		"$SCRIPTS_DIR/mk-rootfs.sh"
		"$SCRIPTS_DIR/mk-recovery.sh"
	fi

	if [ "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-firmware.sh"
	"$SCRIPTS_DIR/mk-updateimg.sh"

	finish_build
}

# 编译所有buildroot镜像并打包
build_buildroot()
{
	echo "=========================================="
	echo "          Start building buildroot all images"
	echo "=========================================="
	export RK_ROOTFS_SYSTEM=buildroot
	rm -rf $RK_FIRMWARE_DIR
	mkdir -p $RK_FIRMWARE_DIR

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ -z "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-security.sh" security_check

	if [ "$RK_KERNEL_CFG" ]; then
		"$SCRIPTS_DIR/mk-kernel.sh"
		"$SCRIPTS_DIR/mk-rootfs.sh"
		"$SCRIPTS_DIR/mk-recovery.sh"
	fi

	if [ "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-firmware.sh"
	"$SCRIPTS_DIR/mk-updateimg.sh"

	finish_build
}

# 编译所有debian11镜像并打包
build_debian11_all()
{
	echo "=========================================="
	echo "          Start building debian11 all images"
	echo "=========================================="
	export RK_ROOTFS_SYSTEM=debian11
	rm -rf $RK_FIRMWARE_DIR
	mkdir -p $RK_FIRMWARE_DIR

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ -z "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-security.sh" security_check

	if [ "$RK_KERNEL_CFG" ]; then
		"$SCRIPTS_DIR/mk-kernel.sh"
		"$SCRIPTS_DIR/mk-rootfs.sh"
		"$SCRIPTS_DIR/mk-recovery.sh"
	fi

	if [ "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-firmware.sh"
	"$SCRIPTS_DIR/mk-updateimg.sh"

	finish_build
}

# 编译所有debian12镜像并打包
build_debian12_all()
{
	echo "=========================================="
	echo "          Start building debian12 all images"
	echo "=========================================="
	export RK_ROOTFS_SYSTEM=debian12
	rm -rf $RK_FIRMWARE_DIR
	mkdir -p $RK_FIRMWARE_DIR

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ -z "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-security.sh" security_check

	if [ "$RK_KERNEL_CFG" ]; then
		"$SCRIPTS_DIR/mk-kernel.sh"
		"$SCRIPTS_DIR/mk-rootfs.sh"
		"$SCRIPTS_DIR/mk-recovery.sh"
	fi

	if [ "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-firmware.sh"
	"$SCRIPTS_DIR/mk-updateimg.sh"

	finish_build
}

# 编译所有ubuntu20镜像并打包
build_ubuntu20_all()
{
	echo "=========================================="
	echo "          Start building ubuntu20 all images"
	echo "=========================================="
	export RK_ROOTFS_SYSTEM=ubuntu20
	rm -rf $RK_FIRMWARE_DIR
	mkdir -p $RK_FIRMWARE_DIR

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ -z "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-security.sh" security_check

	if [ "$RK_KERNEL_CFG" ]; then
		"$SCRIPTS_DIR/mk-kernel.sh"
		"$SCRIPTS_DIR/mk-rootfs.sh"
		"$SCRIPTS_DIR/mk-recovery.sh"
	fi

	if [ "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-firmware.sh"
	"$SCRIPTS_DIR/mk-updateimg.sh"

	finish_build
}

# 编译所有ubuntu22镜像并打包
build_ubuntu22_all()
{
	echo "=========================================="
	echo "          Start building ubuntu22 all images"
	echo "=========================================="
	export RK_ROOTFS_SYSTEM=ubuntu22
	rm -rf $RK_FIRMWARE_DIR
	mkdir -p $RK_FIRMWARE_DIR

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ -z "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-security.sh" security_check

	if [ "$RK_KERNEL_CFG" ]; then
		"$SCRIPTS_DIR/mk-kernel.sh"
		"$SCRIPTS_DIR/mk-rootfs.sh"
		"$SCRIPTS_DIR/mk-recovery.sh"
	fi

	if [ "$RK_SECURITY" ];then
		"$SCRIPTS_DIR/mk-loader.sh"
	fi

	"$SCRIPTS_DIR/mk-firmware.sh"
	"$SCRIPTS_DIR/mk-updateimg.sh"

	finish_build
}

# 编译完成后的后处理函数
build_save()
{
	echo "=========================================="
	echo "          Start saving images and build info"
	echo "=========================================="

	shift
	SAVE_BASE_DIR="$RK_OUTDIR/$BOARD${1:+/$1}"
	case "$(grep "^ID=" "$RK_OUTDIR/os-release" 2>/dev/null)" in
		ID=buildroot) SAVE_DIR="$SAVE_BASE_DIR/BUILDROOT" ;;
		ID=debian) SAVE_DIR="$SAVE_BASE_DIR/DEBIAN" ;;
		ID=ubuntu) SAVE_DIR="$SAVE_BASE_DIR/UBUNTU" ;;
		ID=poky) SAVE_DIR="$SAVE_BASE_DIR/YOCTO" ;;
		*) SAVE_DIR="$SAVE_BASE_DIR" ;;
	esac
	[ "$1" ] || SAVE_DIR="$SAVE_DIR/$(date  +%Y%m%d_%H%M%S)"
	mkdir -p "$SAVE_DIR"
	rm -rf "$SAVE_BASE_DIR/latest"
	ln -rsf "$SAVE_DIR" "$SAVE_BASE_DIR/latest"

	echo "Saving into $SAVE_DIR..."

	if [ "$RK_KERNEL_CFG" ]; then
		mkdir -p "$SAVE_DIR/kernel"

		echo "Saving linux-headers..."
		"$SCRIPTS_DIR/mk-kernel.sh" linux-headers \
			"$SAVE_DIR/kernel"

		echo "Saving kernel files..."
		cp kernel/.config kernel/System.map kernel/vmlinux \
			$RK_KERNEL_DTB "$SAVE_DIR/kernel"
	fi

	echo "Saving images..."
	mkdir -p "$SAVE_DIR/IMAGES"
	cp "$RK_FIRMWARE_DIR"/* "$SAVE_DIR/IMAGES/"

	echo "Saving build info..."
	if yes | ${PYTHON3:-python3} .repo/repo/repo manifest -r \
		-o "$SAVE_DIR/manifest.xml"; then
		# Only do this when repositories are available
		echo "Saving patches..."
		PATCHES_DIR="$SAVE_DIR/PATCHES"
		mkdir -p "$PATCHES_DIR"
		# .repo/repo/repo forall -j $(( $CPUS + 1 )) -c \
			"\"$SCRIPTS_DIR/save-patches.sh\" \
			\"$PATCHES_DIR/\$REPO_PATH\" \$REPO_PATH \$REPO_LREV"
		install -D -m 0755 "$RK_DATA_DIR/misc/apply-all.sh" \
			"$PATCHES_DIR"
	fi

	cp "$RK_FINAL_ENV" "$RK_CONFIG" "$RK_DEFCONFIG_LINK" "$SAVE_DIR/"
	cp "$RK_CONFIG" "$SAVE_DIR/build_info"

	echo "Saving build logs..."
	cp -rp "$RK_LOG_BASE_DIR" "$SAVE_DIR/"

	finish_build
}

# 编译所有并进行后处理
build_allsave()
{
	echo "=========================================="
	echo "          Start building allsave"
	echo "=========================================="

	build_all
	build_save $@

	finish_build
}

# 打印帮助信息
usage_hook()
{
	echo -e "all                               \tbuild all images"
	echo -e "buildroot_update		\tbuild buildroot all images"
	echo -e "debian11_update			\tbuild debian11 all images"
	echo -e "debian12_update			\tbuild debian12 all images"
	echo -e "ubuntu20_update			\tbuild ubuntu20 all images"
	echo -e "ubuntu22_update 		\tbuild ubuntu22 all images"
}

clean_hook()
{
	rm -rf "$RK_OUTDIR"/$BOARD*
}

BUILD_CMDS="all buildroot_update debian11_update debian12_update ubuntu20_update ubuntu22_update"

# 编译全部镜像的钩子函数
build_hook()
{
	case "$1" in
		all) build_all ;;
		buildroot_update ) build_buildroot ;;
		debian11_update ) build_debian11_all ;;
		debian12_update ) build_debian12_all ;;
		ubuntu20_update ) build_ubuntu20_all ;;
		ubuntu22_update ) build_ubuntu22_all ;;
	esac
}

POST_BUILD_CMDS="save"
post_build_hook()
{
	build_save $@
}

source "${BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

case "$1" in
	all) build_all ;;
	buildroot_update ) build_all ;;
	debian11_update ) build_debian11_all ;;
	debian12_update ) build_debian12_all ;;
	ubuntu20_update ) build_ubuntu20_all ;;
	ubuntu22_update ) build_ubuntu22_all ;;
	*) usage ;;
esac
