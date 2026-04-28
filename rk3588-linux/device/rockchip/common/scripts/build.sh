#!/bin/bash

# 在发生错误时调用名为 err_handler 的函数来处理错误，并启用错误处理机制
trap 'err_handler' ERR
set -eE

# 导入一些要用的函数
source $(dirname "$(realpath "$BASH_SOURCE")")/general.sh

# 检查是否第一次运行,如果是第一次运行将安装一些需要的依赖、设置python脚本和交换分区
if [ ! -f "$SDK_DIR/script_run_flag" ]; then
    # 如果是第一次运行,则获取 sudo 权限
    echo -e "\e[31m这是第一次运行脚本，请输入您的用户密码.\e[0m"
    install_package
    # 创建一个标志文件,表示脚本已经运行过一次
    touch "$SDK_DIR/script_run_flag"
    set_python
fi

# 如果命令行参数为 "make-targets" 或 "make-usage"
# 执行 run_build_hooks 函数并退出脚本
case "$@" in
	make-targets | make-usage)
		run_build_hooks "$@"
		exit 0 ;;
esac

# 设置log日志打印，将日志保存到output/log
set_log

# 创建目录 $RK_FIRMWARE_DIR ,最后会链接到根目录的rockdev
mkdir -p "$RK_FIRMWARE_DIR"
rm -rf "$SDK_DIR/rockdev"
ln -rsf "$RK_FIRMWARE_DIR" "$SDK_DIR/rockdev"

# 返回根目录
cd "$SDK_DIR"

# 如果输入的参数为空，则进入图形界面，否则为命令行编译
if [ -z "$1" ]; then
        titlestr="Choose an option"
        backtitle="iTOP-RK3588 building script, http://www.topeet.com"
        menustr="Compile image | uboot | kernel | rootfs | recovery | all | firmware |updateimg | cleanall"
        TTY_X=$(($(stty size | awk '{print $2}')-6))                    # determine terminal width
        TTY_Y=$(($(stty size | awk '{print $1}')-6))                    # determine terminal height

        # 第1页选项数组，包含选项和对应的函数名
        choose_page1+=("uboot" "uboot")
        choose_page1+=("kernel" "kernel")
        choose_page1+=("rootfs" "rootfs")
        choose_page1+=("recovery" "recovery")
        choose_page1+=("all_img" "all")
        choose_page1+=("firmware" "firmware")
        choose_page1+=("updateimg" "updateimg")
        choose_page1+=("cleanall" "cleanall")

        # 第2页选项数组，包含选项和对应的函数名
        choose_page2+=("buildroot" "buildroot")
        choose_page2+=("debian11" "debian11")
        choose_page2+=("debian12" "debian12")
        choose_page2+=("ubuntu20" "ubuntu20")
        choose_page2+=("ubuntu22" "ubuntu22")

        # 第3页选项数组，包含选项和对应的函数名
        choose_page3+=("buildroot_update" "buildroot")
        choose_page3+=("debian11_update" "debian11")
        choose_page3+=("debian12_update" "debian12")
        choose_page3+=("ubuntu20_update" "ubuntu20")
        choose_page3+=("ubuntu22_update" "ubuntu22")

        OPTIONS=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
                                                        --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
                                                        --cancel-button Exit --ok-button Select "${choose_page1[@]}" \
                                                        3>&1 1>&2 2>&3)
else
        OPTIONS="$@"
fi

# 根据用户选择的选项，判断是否需要显示第2页菜单
if [[ $OPTIONS == "rootfs" ]]; then
    titlestr="Choose an option"
    backtitle="iTOP-RK3588 building script, http://www.topeet.com"
    menustr="Compile single rootfs img | buildroot | debian11 | debian12 | ubuntu20 | ubuntu22"
    # 使用whiptail创建第二页菜单，保存用户选择的选项到变量OPTIONS中
    OPTIONS=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
                        --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
                        --cancel-button Exit --ok-button Select "${choose_page2[@]}" \
                        3>&1 1>&2 2>&3)
fi

# 根据用户选择的选项，判断是否需要显示第3页菜单
if [[ $OPTIONS == "all_img" ]]; then

    titlestr="Choose an option"
    backtitle="iTOP-RK3588 building script, http://www.topeet.com"
    menustr="Compile update.img image | buildroot | debian11 | debian12 | ubuntu20 | ubuntu22 "
    # 使用whiptail创建第3页菜单，保存用户选择的选项到变量OPTIONS中
    OPTIONS=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
                        --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
                        --cancel-button Exit --ok-button Select "${choose_page3[@]}" \
                        3>&1 1>&2 2>&3)
fi

# 获取支持的命令列表，并存储到变量 CMDS 中
CMDS="$(run_build_hooks support-cmds all | xargs)"

for opt in $OPTIONS; do
	case "$opt" in
		help | h | -h | --help | usage | \?) usage ;;
		shell | cleanall)
			# 如果选项为 shell 或 cleanall，并且它是唯一的选项（没有其他选项），则跳出循环
			if [ "$opt" = "$OPTIONS" ]; then
				break
			fi
			echo "ERROR: $opt cannot combine with other options!"
			;;
		post-rootfs)
			# 如果选项为 post-rootfs，并且它是第一个选项，并且后面跟着一个 rootfs 目录，则隐藏其他参数并跳出循环
			if [ "$opt" = "$1" -a -d "$2" ]; then
				# Hide other args from build stages
				OPTIONS=$opt
				break
			fi

			echo "ERROR: $opt should be the first option followed by rootfs dir!"
			;;
		*)
			# 对于其他选项，则需要通过option_check检查
			if option_check "$CMDS" $opt; then
				continue
			fi

			echo "ERROR: Unhandled option: $opt"
			;;
	esac
	usage
done

# 运行 init 钩子函数 (preparing SDK configs, etc.)
run_build_hooks init rockchip_rk3588_topeet_defconfig

# 打开强制导出环境变量
set -a

# 加载配置环境变量文件 $RK_CONFIG
source "$RK_CONFIG"
cp "$RK_CONFIG" "$RK_LOG_DIR"

# 导入分区帮助脚本
source "$PARTITION_HELPER"

# 运行分区初始化函数
rk_partition_init

# 停止强制导出环境变量
set +a

# 设置交叉编译器
set_toolchain

# 处理特殊命令
case "$OPTIONS" in
	cleanall)
		run_build_hooks clean
		rm -rf "$RK_OUTDIR"
		finish_build cleanall
		exit 0 ;;
	post-rootfs)
		shift
		run_post_hooks $@
		finish_build post-rootfs
		exit 0 ;;
esac

# 打印配置的环境变量
# print_env

# 预构建阶段（子模块配置等）
run_build_hooks pre-build  $OPTIONS

# 运行 build 钩子函数，并传递选项参数
run_build_hooks build $OPTIONS

# 运行 post-build 钩子函数，并传递选项参数
run_build_hooks post-build $OPTIONS


