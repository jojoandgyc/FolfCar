#!/bin/bash -e
# message fatal 不同颜色的信息打印
# partition_size_kb 获取分区大小
# link_image 软链接镜像
# pack_extra_partitions 打包额外的分区
# build_firmware构建固件
# usage_hook 帮助信息打印
# clean_hook 清理信息
# post_build_hook 运行钩子函数


# 打印信息
message() {
	echo -e "\e[36m$@\e[0m"
}

# 打印信息
fatal() {
	echo -e "\e[31m$@\e[0m"
	exit 1
}

# 获取分区大小
partition_size_kb() {
	PART_SIZE="$(rk_partition_size "$1")"
	echo $(( ${PART_SIZE:-0} / 2))
}

# 软链接镜像
link_image() {
	SRC="$1"
	DST="$2"
	message "Linking $DST from $SRC..."
	ln -rsf "$SRC" "$RK_FIRMWARE_DIR/$DST"
}

# 打包额外的分区
pack_extra_partitions() {
	for idx in $(seq 1 "$(rk_extra_part_num)"); do
		# Skip built-in partitions
		if rk_extra_part_builtin $idx; then
			continue
		fi

		PART_NAME="$(rk_extra_part_name $idx)"
		FS_TYPE="$(rk_extra_part_fstype $idx)"
		SIZE="$(rk_extra_part_size $idx)"
		FAKEROOT_SCRIPT="$(rk_extra_part_fakeroot_script $idx)"
		OUTDIR="$(rk_extra_part_outdir $idx)"
		DST="$(rk_extra_part_img $idx)"

		if [ -z "$(rk_extra_part_src $idx)" ]; then
			echo "Ignoring $PART_NAME for no sources"
			continue
		fi

		rk_extra_part_prepare $idx

		if [ "$SIZE" = max ]; then
			SIZE="$(partition_size_kb "$PART_NAME")K"
			if [ "$SIZE" = 0K ]; then
				fatal "Unable to detect max size of $PART_NAME"
			fi

			echo "Using maxium size: $SIZE"
		fi

		sed -i '/mk-image.sh/d' "$FAKEROOT_SCRIPT"
		echo "\"$SCRIPTS_DIR/mk-image.sh\" \
			\"$OUTDIR\" \"$DST\" \"$FS_TYPE\" \
			\"$SIZE\" \"$PART_NAME\"" >> "$FAKEROOT_SCRIPT"

		message "Packing $DST from $FAKEROOT_SCRIPT"
		cd "$OUTDIR"
		fakeroot -- "$FAKEROOT_SCRIPT"
		message "Done packing $DST"
	done
}

# 构建固件
build_firmware()
{
	if ! which fakeroot &>/dev/null; then
		echo "fakeroot not found! (sudo apt-get install fakeroot)"
		exit 1
	fi

	mkdir -p "$RK_FIRMWARE_DIR"

	link_image "$CHIP_DIR/$RK_PARAMETER" parameter.txt
	[ -z "$RK_MISC_IMG" ] || \
		link_image "$RK_IMAGE_DIR/$RK_MISC_IMG" misc.img

	pack_extra_partitions

	echo "Packed files:"
	for f in "$RK_FIRMWARE_DIR"/*; do
		NAME=$(basename "$f")

		echo -n "$NAME"
		if [ -L "$f" ]; then
			echo -n "($(readlink -f "$f"))"
		fi

		FILE_SIZE=$(ls -lLh $f | xargs | cut -d' ' -f 5)
		echo ": $FILE_SIZE"

		echo "$NAME" | grep -q ".img$" || continue

		# Assert the image's size smaller then the limit
		PART_SIZE_KB="$(partition_size_kb "${NAME%.img}")"
		[ ! "$PART_SIZE_KB" -eq 0 ] || continue

		FILE_SIZE_KB="$(( $(stat -Lc "%s" "$f") / 1024 ))"
		if [ "$PART_SIZE_KB" -lt "$FILE_SIZE_KB" ]; then
			fatal "error: $NAME's size exceed parameter's limit!"
		fi
	done

	message "Images in $RK_FIRMWARE_DIR are ready!"

	finish_build
}

# 帮助信息打印
usage_hook()
{
	echo -e "firmware                          \tpack and check firmwares"
}

# 清理信息
clean_hook()
{
	rm -rf "$RK_FIRMWARE_DIR"
	mkdir -p "$RK_FIRMWARE_DIR"
}

POST_BUILD_CMDS="firmware"

# 运行钩子函数
post_build_hook()
{
	echo "=========================================="
	echo "          Start packing firmwares"
	echo "=========================================="

	build_firmware
}

source "${BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

post_build_hook $@
