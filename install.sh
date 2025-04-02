#!/bin/bash

SOFTWARE_NAME="clewdr"
GITHUB_REPO="Xerxes-2/clewdr"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/clewdr"
GH_PROXY="https://ghfast.top/"
GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
VERSION_FILE="${TARGET_DIR}/version.txt"
PORT=8484

handle_error() {
    echo "错误：${2}"
    exit ${1}
}

detect_system() {
    echo "检测系统环境..."
    
    if [[ -n "$PREFIX" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        IS_TERMUX=true
        echo "检测到Termux环境"
    else
        IS_TERMUX=false
        
        if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -q -i 'musl'; then
            IS_MUSL=true
            echo "检测到MUSL Linux环境"
        else
            IS_MUSL=false
            echo "检测到标准Linux环境(glibc)"
        fi
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armv8l) handle_error 1 "暂不支持32位ARM架构 ($ARCH)" ;;
        *) handle_error 1 "不支持的系统架构: $ARCH" ;;
    esac
    echo "检测到架构: $ARCH"
    
    if [ "$IS_TERMUX" = true ] && [ "$ARCH" != "aarch64" ]; then
        handle_error 1 "Termux环境仅支持aarch64架构"
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        PACKAGE_MANAGER="pkg"
        INSTALL_CMD="pkg install -y"
    elif command -v apt >/dev/null 2>&1; then
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
    fi
    
    [ -n "$PACKAGE_MANAGER" ] && echo "使用包管理器: $PACKAGE_MANAGER"
}

install_dependencies() {
    echo "检查并安装依赖..."
    local dependencies=("curl" "unzip" "ldd")
    local missing_deps=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo "所有依赖已安装"
        return 0
    fi
    
    if [ "$PACKAGE_MANAGER" = "unknown" ] || [ -z "$INSTALL_CMD" ]; then
        handle_error 1 "缺少以下依赖，但无法自动安装: ${missing_deps[*]}"
    fi
    
    echo "安装缺失的依赖: ${missing_deps[*]}"
    
    case "$PACKAGE_MANAGER" in
        apt|pkg) apt update || pkg update ;;
        pacman) pacman -Sy ;;
        zypper) zypper refresh ;;
        apk) apk update ;;
    esac
    
    if ! $INSTALL_CMD "${missing_deps[@]}"; then
        handle_error 1 "依赖安装失败，请手动安装: ${missing_deps[*]}"
    fi
    
    for dep in "${missing_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error 1 "依赖 $dep 安装失败，请手动安装"
        fi
    done
    
    echo "依赖安装完成"
}

check_version() {
    echo "检查软件版本..."
    
    if [ ! -d "$TARGET_DIR" ]; then
        echo "未检测到已安装版本，将执行首次安装"
        return 0
    fi
    
    if [ ! -f "$VERSION_FILE" ]; then
        echo "未找到版本信息文件，将重新安装最新版本"
        return 0
    fi
    
    LOCAL_VERSION=$(cat "$VERSION_FILE")
    echo "当前已安装版本: $LOCAL_VERSION"
    
    echo "正在检查最新版本..."
    
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local api_url="$GH_API_URL"
    local use_proxy=false
    
    if [ -n "$country_code" ] && [ "$country_code" = "CN" ]; then
        echo "检测到中国大陆IP，将使用代理获取版本信息"
        api_url="${GH_PROXY}${GH_API_URL}"
        use_proxy=true
    fi
    
    local latest_info=$(curl -s --connect-timeout 10 "$api_url")
    if [ -z "$latest_info" ]; then
        echo "无法获取最新版本信息，将保持当前版本"
        return 1
    fi
    
    LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    fi
    
    if [ -z "$LATEST_VERSION" ]; then
        echo "解析版本信息失败，将保持当前版本"
        return 1
    fi
    
    echo "最新版本: $LATEST_VERSION"
    
    if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
        echo "已是最新版本，无需更新"
        read -p "是否强制重新安装？(y/N): " force_update
        if [[ "$force_update" =~ ^[Yy]$ ]]; then
            echo "将强制重新安装..."
            return 0
        else
            return 1
        fi
    else
        echo "发现新版本，将更新到 $LATEST_VERSION"
        return 0
    fi
}

setup_download_url() {
    echo "检测IP地理位置..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "检测到国家代码: $country_code"
        
        if [ "$country_code" = "CN" ]; then
            echo "检测到中国大陆IP，默认启用GitHub代理: $GH_PROXY"
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
    
    if [ "$IS_TERMUX" = true ]; then
        DOWNLOAD_FILENAME="$SOFTWARE_NAME-android-aarch64.zip"
    elif [ "$IS_MUSL" = true ]; then
        DOWNLOAD_FILENAME="$SOFTWARE_NAME-musllinux-$ARCH.zip"
        echo "检测到musl环境，自动选择musl版本"
    else
        echo "检测到glibc环境"
        echo "请选择要下载的二进制文件类型:"
        echo "glibc版本号不足2.38的系统请使用musl版本"
        echo "glibc版本号可使用 'ldd --version' 命令查看"
        echo "1) glibc 版本 (标准 Linux 版本，推荐)"
        echo "2) musl 版本 (适用于 Alpine 等使用 musl 的系统)"
        read -p "请输入选择 [1-2] (默认1): " libc_choice
        
        case "${libc_choice:-1}" in
            2)
                DOWNLOAD_FILENAME="$SOFTWARE_NAME-musllinux-$ARCH.zip"
                echo "已选择 musl 版本"
                ;;
            *)
                DOWNLOAD_FILENAME="$SOFTWARE_NAME-linux-$ARCH.zip"
                echo "已选择 glibc 版本"
                ;;
        esac
    fi
    
    echo "使用版本: $DOWNLOAD_FILENAME"
}

download_and_install() {
    echo "准备目标目录..."
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR"
        echo "创建目标目录: $TARGET_DIR"
    else
        echo "目标目录已存在，将覆盖重复文件"
    fi
    
    local download_url="$GH_DOWNLOAD_URL/$DOWNLOAD_FILENAME"
    local download_path="$TARGET_DIR/$DOWNLOAD_FILENAME"
    echo "下载: $download_url"
    
    local max_retries=3
    local retry_count=0
    local wait_time=5
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$download_url" -o "$download_path" -#; then
            echo ""
            if [ -f "$download_path" ] && [ -s "$download_path" ]; then
                break
            fi
        fi
        
        echo "下载失败，尝试重试..."
        rm -f "$download_path"
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $max_retries ]; then
            echo "将在 $wait_time 秒后重试 ($retry_count/$max_retries)..."
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            handle_error 1 "下载失败: $download_url"
        fi
    done
    
    echo "解压文件..."
    if ! unzip -o "$download_path" -d "$TARGET_DIR"; then
        rm -f "$download_path"
        handle_error 1 "解压失败: $download_path"
    fi
    
    rm -f "$download_path"
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
    fi
    
    if [ -n "$LATEST_VERSION" ]; then
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        echo "版本信息已保存: $LATEST_VERSION"
    fi
    
    echo "安装完成！"
    echo "===================="
    echo "$SOFTWARE_NAME 已安装到: $TARGET_DIR"
    echo "你可以运行: $TARGET_DIR/$SOFTWARE_NAME 来运行程序"
    echo "===================="
}

open_port() {
    echo "正在尝试开放端口 $PORT..."
    
    if [ "$EUID" -ne 0 ] && [ "$IS_TERMUX" = false ]; then
        echo "注意: 需要使用root权限来开放端口，当前非root用户"
        read -p "是否尝试使用sudo开放端口？(y/N): " use_sudo
        if [[ ! "$use_sudo" =~ ^[Yy]$ ]]; then
            echo "跳过端口开放，请手动开放端口 $PORT"
            return
        fi
        HAS_SUDO=true
    else
        HAS_SUDO=false
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        echo "Termux环境无需手动开放端口，应用将自动使用 $PORT 端口"
        return
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo "检测到firewalld服务"
        if [ "$HAS_SUDO" = true ]; then
            sudo firewall-cmd --zone=public --add-port=$PORT/tcp --permanent && \
            sudo firewall-cmd --reload && \
            echo "已成功开放端口 $PORT (firewalld)"
        else
            firewall-cmd --zone=public --add-port=$PORT/tcp --permanent && \
            firewall-cmd --reload && \
            echo "已成功开放端口 $PORT (firewalld)"
        fi
    elif command -v ufw >/dev/null 2>&1; then
        echo "检测到ufw服务"
        if [ "$HAS_SUDO" = true ]; then
            sudo ufw allow $PORT/tcp && \
            sudo ufw reload && \
            echo "已成功开放端口 $PORT (ufw)"
        else
            ufw allow $PORT/tcp && \
            ufw reload && \
            echo "已成功开放端口 $PORT (ufw)"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        echo "使用iptables开放端口"
        if [ "$HAS_SUDO" = true ]; then
            sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT && \
            echo "已使用iptables开放端口 $PORT"
            echo "注意：该设置可能不会在系统重启后保留，请考虑将其添加到系统启动脚本中"
        else
            iptables -A INPUT -p tcp --dport $PORT -j ACCEPT && \
            echo "已使用iptables开放端口 $PORT"
            echo "注意：该设置可能不会在系统重启后保留，请考虑将其添加到系统启动脚本中"
        fi
    else
        echo "未检测到支持的防火墙服务，请手动开放端口 $PORT"
    fi
    
    if command -v getenforce >/dev/null 2>&1; then
        selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            echo "检测到SELinux处于活动状态，尝试配置SELinux策略..."
            if command -v semanage >/dev/null 2>&1; then
                if [ "$HAS_SUDO" = true ]; then
                    sudo semanage port -a -t http_port_t -p tcp $PORT || \
                    echo "SELinux端口配置未成功，可能需要手动配置"
                else
                    semanage port -a -t http_port_t -p tcp $PORT || \
                    echo "SELinux端口配置未成功，可能需要手动配置"
                fi
            else
                echo "未找到semanage命令，无法自动配置SELinux策略"
                echo "如遇到权限问题，请手动配置SELinux允许程序使用端口 $PORT"
            fi
        fi
    fi
    
    echo "端口 $PORT 配置完成"
}

run_program() {
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        read -p "是否立即运行 $SOFTWARE_NAME？(y/N): " run_now
        if [[ "$run_now" =~ ^[Yy]$ ]]; then
            echo "正在启动 $SOFTWARE_NAME..."
            cd "$TARGET_DIR" && ./"$SOFTWARE_NAME"
        else
            echo "你可以稍后通过运行: $TARGET_DIR/$SOFTWARE_NAME 来运行程序"
        fi
    else
        echo "警告: 未找到可执行文件 $TARGET_DIR/$SOFTWARE_NAME"
    fi
}

main() {
    echo "开始安装 $SOFTWARE_NAME..."
    detect_system
    install_dependencies
    
    if ! check_version; then
        echo "已取消安装/更新操作"
        exit 0
    fi
    
    setup_download_url
    download_and_install
    open_port
    run_program
}

main