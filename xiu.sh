#!/bin/bash

# 修复 vtoyboot.sh 运行错误的脚本 (v3 - Bind Mount)

echo "**********************************************"
echo "      vtoyboot 修复脚本 (v3)"
echo "**********************************************"

# 检查是否以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
   echo "此脚本必须以 root 身份运行" 1>&2
   exit 1
fi

# 创建一个临时目录用于绑定挂载
TMP_DIR=$(mktemp -d)
if [ ! -d "$TMP_DIR" ]; then
    echo "创建临时目录失败。"
    exit 1
fi

# 定义需要变为可写的目录
# /sbin 通常是 /usr/sbin 的符号链接, 但我们同时处理以确保兼容性
TARGET_DIRS_TO_BIND=("/usr/sbin" "/sbin" "/usr/share/initramfs-tools/hooks")
declare -A MOUNTED_POINTS

cleanup() {
    echo ""
    echo "正在清理环境..."
    for d in "${!MOUNTED_POINTS[@]}"; do
        echo "正在卸载 $d ..."
        umount "$d" 2>/dev/null
    done
    echo "正在删除临时文件..."
    rm -rf "$TMP_DIR"
    echo "清理完成。"
}

# 设置一个 trap, 无论脚本是成功还是失败退出, 都会执行 cleanup 函数
trap cleanup EXIT

echo "正在准备可写环境 (bind mount)..."
for DIR in "${TARGET_DIRS_TO_BIND[@]}"; do
    # 检查原始目录是否存在
    if [ ! -d "$DIR" ]; then
        echo "警告: 目录 $DIR 不存在，跳过。"
        continue
    fi
    
    # 检查是否已经处理过这个真实路径 (处理 /sbin -> /usr/sbin 的情况)
    REAL_DIR_PATH=$(realpath "$DIR")
    if [[ -v MOUNTED_POINTS["$REAL_DIR_PATH"] ]]; then
        echo "信息: $DIR 的真实路径 $REAL_DIR_PATH 已经处理过，跳过。"
        continue
    fi

    TMP_MIRROR="$TMP_DIR/$(echo "$REAL_DIR_PATH" | sed 's#^/##g')"
    mkdir -p "$TMP_MIRROR"
    
    # 将原始目录的内容复制到临时目录
    # 使用 rsync 可以更好地处理符号链接和权限
    if ! rsync -a -q "$REAL_DIR_PATH/" "$TMP_MIRROR/"; then
        echo "错误: 从 $REAL_DIR_PATH 复制文件到临时目录失败。"
        exit 1
    fi
    
    # 使用绑定挂载将可写目录覆盖到原始目录
    if ! mount --bind "$TMP_MIRROR" "$REAL_DIR_PATH"; then
        echo "错误: 绑定挂载 $REAL_DIR_PATH 失败。"
        exit 1
    fi
    
    echo "成功挂载 $REAL_DIR_PATH"
    MOUNTED_POINTS["$REAL_DIR_PATH"]=1
done


# 检查 vtoyboot.sh 是否存在
if [ ! -f "vtoyboot.sh" ]; then
    echo "错误: vtoyboot.sh 不在当前目录中。"
    echo "请将此脚本与 vtoyboot.sh 放在同一目录下运行。"
    exit 1
fi

# 执行原始脚本
echo ""
echo "现在执行 vtoyboot.sh ..."
echo "----------------------------------------------"
bash vtoyboot.sh
echo "----------------------------------------------"
echo "vtoyboot.sh 执行完毕。"
echo ""

# cleanup 函数将会在脚本退出时自动调用

echo "修复过程完成。" 
