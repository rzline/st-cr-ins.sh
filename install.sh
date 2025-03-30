#!/bin/bash

SOFTWARE_NAME="clewdr"    # 软件名称
GITHUB_REPO="Xerxes-2/clewdr"   # GitHub仓库地址

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/clewdr"
IS_TERMUX=false
IS_MUSL=false
ARCH=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_PROXY="https://ghfast.top/"
GH_DOWNLOAD_URL=""

handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo "错误：${error_msg}"
    exit ${exit_code}
}

# 检测运行环境
detect_environment() {
    echo "检测运行环境..."
    
    if [[ -n "$PREFIX" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        IS_TERMUX=true
        echo "检测到Termux环境"
    else
        IS_TERMUX=false
        
        if command -v ldd >/dev/null 2>&1; then
            if ldd --version 2>&1 | grep -q -i 'musl'; then
                IS_MUSL=true
                echo "检测到MUSL Linux环境"
            else
                IS_MUSL=false
                echo "检测到标准Linux环境(glibc)"
            fi
        else
            IS_MUSL=false
            echo "无法确定是否为MUSL环境(缺少ldd)，按标准Linux处理"
        fi
    fi
}

# 检测系统架构
detect_architecture() {
    echo "检测系统架构..."
    local arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            ARCH="x86_64"
            ;;
        amd64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        armv7l|armv8l)
            handle_error 1 "暂不支持32位ARM架构 ($arch)"
            ;;
        *)
            handle_error 1 "不支持的系统架构: $arch"
            ;;
    esac
    
    echo "检测到架构: $ARCH"
    
    # Termux特殊处理
    if [ "$IS_TERMUX" = true ] && [ "$ARCH" != "aarch64" ]; then
        handle_error 1 "Termux环境仅支持aarch64架构"
    fi
}

detect_package_manager() {
    echo "检测包管理器..."
    
    if [ "$IS_TERMUX" = true ]; then
        PACKAGE_MANAGER="pkg"
        INSTALL_CMD="pkg install -y"
        echo "使用包管理器: pkg (Termux)"
        return
    fi
    
    # 检测各种包管理器
    if command -v apt >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="apt install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        INSTALL_CMD="yum install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="zypper install -y"
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER="apk"
        INSTALL_CMD="apk add"
    else
        echo "警告: 未检测到支持的包管理器，将跳过依赖安装"
        PACKAGE_MANAGER="unknown"
        INSTALL_CMD=""
        return
    fi
    
    echo "使用包管理器: $PACKAGE_MANAGER"
}

# 安装依赖
install_dependencies() {
    echo "检查并安装依赖..."
    local dependencies=("curl" "unzip")
    local missing_deps=()
    
    # 检查哪些依赖缺失
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    # 如果没有缺失的依赖，直接返回
    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo "所有依赖已安装"
        return 0
    fi
    
    # 如果包管理器未知，无法安装
    if [ "$PACKAGE_MANAGER" = "unknown" ] || [ -z "$INSTALL_CMD" ]; then
        handle_error 1 "缺少以下依赖，但无法自动安装: ${missing_deps[*]}"
    fi
    
    echo "安装缺失的依赖: ${missing_deps[*]}"
    
    # 尝试更新包管理器索引（不同的包管理器有不同的命令）
    case "$PACKAGE_MANAGER" in
        apt|pkg)
            apt update || pkg update
            ;;
        dnf|yum)
            # dnf和yum通常不需要显式更新
            ;;
        pacman)
            pacman -Sy
            ;;
        zypper)
            zypper refresh
            ;;
        apk)
            apk update
            ;;
    esac
    
    # 安装依赖
    if [ ${#missing_deps[@]} -gt 0 ]; then
        if ! $INSTALL_CMD "${missing_deps[@]}"; then
            handle_error 1 "依赖安装失败，请手动安装: ${missing_deps[*]}"
        fi
    fi
    
    # 检查安装是否成功
    for dep in "${missing_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error 1 "依赖 $dep 安装失败，请手动安装"
        fi
    done
    
    echo "依赖安装完成"
}

# 检测IP位置
detect_country() {
    echo "检测IP地理位置..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "检测到国家代码: $country_code"
        
        if [ "$country_code" = "CN" ]; then
            echo "检测到中国大陆IP，默认启用GitHub代理: $GH_PROXY"
            
            # 询问是否禁用代理
            read -p "是否禁用GitHub代理？(y/N): " disable_proxy
            if [[ "$disable_proxy" =~ ^[Yy]$ ]]; then
                GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
                echo "已禁用GitHub代理，将直连GitHub"
            else
                GH_DOWNLOAD_URL="${GH_PROXY}${GH_DOWNLOAD_URL_BASE}"
                echo "使用GitHub代理: $GH_PROXY"
            fi
        else
            GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
            echo "非中国大陆IP，不使用GitHub代理"
        fi
    else
        echo "无法检测IP地理位置，不使用GitHub代理"
        GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
    fi
}

# 准备目标目录
prepare_target_dir() {
    echo "准备目标目录: $TARGET_DIR"
    
    if [ -d "$TARGET_DIR" ]; then
        echo "目标目录已存在，正在清空..."
        rm -rf "$TARGET_DIR"/*
    else
        mkdir -p "$TARGET_DIR"
    fi
}

# 下载函数
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    local wait_time=5
    
    echo "下载: $url"
    echo "保存到: $output"
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$url" -o "$output" -#; then
            echo ""  # 进度条后换行
            if [ -f "$output" ] && [ -s "$output" ]; then
                echo "下载成功"
                return 0
            else
                echo "下载的文件无效或为空"
                rm -f "$output"
            fi
        else
            echo ""  # 进度条后换行
            echo "下载失败 (错误码: $?)"
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "将在 $wait_time 秒后重试 ($retry_count/$max_retries)..."
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            echo "已达到最大重试次数"
            return 1
        fi
    done
    
    return 1
}

# 执行安装
do_install() {
    echo "开始安装..."
    
    # 确定下载文件名
    local download_filename=""
    
    if [ "$IS_TERMUX" = true ]; then
        download_filename="$SOFTWARE_NAME-android-aarch64.zip"
        echo "使用Termux版本: $download_filename"
    elif [ "$IS_MUSL" = true ]; then
        if [ "$ARCH" = "x86_64" ]; then
            download_filename="$SOFTWARE_NAME-musllinux-x86_64.zip"
        else
            download_filename="$SOFTWARE_NAME-musllinux-arm64.zip"
        fi
        echo "使用MUSL版本: $download_filename"
    else
        if [ "$ARCH" = "x86_64" ]; then
            download_filename="$SOFTWARE_NAME-linux-x86_64.zip"
        else
            download_filename="$SOFTWARE_NAME-linux-arm64.zip"
        fi
        echo "使用标准Linux版本: $download_filename"
    fi
    
    # 下载文件
    local download_url="$GH_DOWNLOAD_URL/$download_filename"
    local download_path="$TARGET_DIR/$download_filename"
    
    if ! download_file "$download_url" "$download_path"; then
        handle_error 1 "下载失败: $download_url"
    fi
    
    # 解压文件
    echo "解压文件到 $TARGET_DIR..."
    if ! unzip -o "$download_path" -d "$TARGET_DIR"; then
        rm -f "$download_path"
        handle_error 1 "解压失败: $download_path"
    fi
    
    # 清理下载的zip文件
    echo "清理临时文件..."
    rm -f "$download_path"
    
    # 设置执行权限
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        echo "设置执行权限..."
        chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
    else
        echo "警告: 未找到主程序文件 $TARGET_DIR/$SOFTWARE_NAME"
    fi
    
    echo "安装完成！"
}

# 主函数
main() {
    echo "开始安装 $SOFTWARE_NAME..."
    
    detect_environment
    detect_architecture
    detect_package_manager
    install_dependencies
    detect_country
    prepare_target_dir
    do_install
    
    echo "===================="
    echo "$SOFTWARE_NAME 已安装到: $TARGET_DIR"
    echo "你可以运行: $TARGET_DIR/$SOFTWARE_NAME"
    echo "===================="
}

# 执行主函数
main
