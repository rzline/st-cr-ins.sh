#!/bin/bash

SOFTWARE_NAME="clewdr"
GITHUB_REPO="Xerxes-2/clewdr"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/clewdr"
GH_PROXY="https://ghfast.top/"
GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
GH_ACTION_URL="https://github.com/${GITHUB_REPO}/actions/workflows/release.yml"
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
    local dependencies=("curl" "unzip")
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

get_installed_version() {
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ] && [ -x "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        local version_output
        version_output=$("$TARGET_DIR/$SOFTWARE_NAME" -V 2>/dev/null)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ] && [ -n "$version_output" ]; then
            INSTALLED_VERSION=$(echo "$version_output" | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" || echo "$version_output")
            echo "通过程序参数检测到版本: $INSTALLED_VERSION"
            return 0
        fi
    fi
    
    if [ -f "$VERSION_FILE" ]; then
        INSTALLED_VERSION=$(cat "$VERSION_FILE")
        echo "从版本文件检测到版本: $INSTALLED_VERSION"
        return 0
    fi
    
    INSTALLED_VERSION=""
    echo "未检测到已安装版本"
    return 1
}

check_version() {
    echo "检查软件版本..."
    
    if [ ! -d "$TARGET_DIR" ]; then
        echo "未检测到已安装目录，将执行首次安装"
        return 0
    fi
    
    get_installed_version
    
    if [ "$USE_BETA" = true ]; then
        echo "已选择安装测试版，将忽略版本检查"
        LATEST_VERSION="beta-$(date +%Y%m%d)"
        return 0
    fi
    
    echo "正在检查最新稳定版本..."
    
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
    
    echo "最新稳定版本: $LATEST_VERSION"
    
    if [ -z "$INSTALLED_VERSION" ]; then
        echo "未检测到已安装版本，将安装最新版本"
        return 0
    fi
    
    if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        echo "已是最新稳定版本，无需更新"
        read -p "是否强制重新安装？(y/N): " force_update
        if [[ "$force_update" =~ ^[Yy]$ ]]; then
            echo "将强制重新安装..."
            return 0
        else
            return 1
        fi
    else
        echo "发现新稳定版本，将从 $INSTALLED_VERSION 更新到 $LATEST_VERSION"
        return 0
    fi
}

select_version() {
    echo "请选择安装版本类型:"
    echo "1) 稳定版 (来自GitHub Releases)"
    echo "2) 测试版 (来自GitHub Actions)"
    
    read -p "请选择 [1/2] (默认:1): " version_choice
    
    case "$version_choice" in
        2)
            USE_BETA=true
            echo "已选择测试版"
            ;;
        *)
            USE_BETA=false
            echo "已选择稳定版"
            ;;
    esac
}

setup_download_url() {
    echo "准备下载链接..."
    
    echo "检测IP地理位置..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local use_proxy=false
    
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "检测到国家代码: $country_code"
        
        if [ "$country_code" = "CN" ]; then
            echo "检测到中国大陆IP，默认启用GitHub代理: $GH_PROXY"
            read -p "是否禁用GitHub代理？(y/N): " disable_proxy
            
            if [[ "$disable_proxy" =~ ^[Yy]$ ]]; then
                use_proxy=false
                echo "已禁用GitHub代理，将直连GitHub"
            else
                use_proxy=true
                echo "使用GitHub代理: $GH_PROXY"
            fi
        else
            echo "非中国大陆IP，不使用GitHub代理"
        fi
    else
        echo "无法检测IP地理位置，不使用GitHub代理"
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        FILE_SUFFIX="android-aarch64"
    elif [ "$IS_MUSL" = true ]; then
        FILE_SUFFIX="musllinux-$ARCH"
    else
        FILE_SUFFIX="linux-$ARCH"
    fi
    
    DOWNLOAD_FILENAME="$SOFTWARE_NAME-$FILE_SUFFIX.zip"
    echo "文件名格式: $DOWNLOAD_FILENAME"
    
    if [ "$USE_BETA" = true ]; then
        echo "正在获取最新测试版构建..."
        GH_DOWNLOAD_URL="https://nightly.link/${GITHUB_REPO}/workflows/dev-build/master/${GITHUB_REPO##*/}-${FILE_SUFFIX}.zip"
        echo "使用测试版下载链接: $GH_DOWNLOAD_URL"
    else
        if [ "$use_proxy" = true ]; then
            GH_DOWNLOAD_URL="${GH_PROXY}${GH_DOWNLOAD_URL_BASE}"
        else
            GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
        fi
    
        echo "使用稳定版下载链接: $GH_DOWNLOAD_URL/$DOWNLOAD_FILENAME"
    fi
}

download_and_install() {
    echo "准备目标目录..."
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR"
        echo "创建目标目录: $TARGET_DIR"
    else
        echo "目标目录已存在，将覆盖重复文件"
    fi
    
    local download_url
    local download_path="$TARGET_DIR/$DOWNLOAD_FILENAME"
    
    if [ "$USE_BETA" = true ]; then
        download_url="$GH_DOWNLOAD_URL"
    else
        download_url="$GH_DOWNLOAD_URL/$DOWNLOAD_FILENAME"
    fi
    
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
    
    local temp_dir="$TARGET_DIR/temp_extract"
    mkdir -p "$temp_dir"
    
    if ! unzip -o "$download_path" -d "$temp_dir"; then
        rm -f "$download_path"
        rm -rf "$temp_dir"
        handle_error 1 "解压失败: $download_path"
    fi
    
    if [ "$USE_BETA" = true ]; then
        echo "处理测试版文件结构..."
        
        local beta_build_path="target/${SOFTWARE_NAME}-${FILE_SUFFIX}/release"
        
        if [ -d "$temp_dir/$beta_build_path" ]; then
            echo "找到测试版构建目录: $beta_build_path"
            
            if [ -f "$temp_dir/$beta_build_path/$SOFTWARE_NAME" ]; then
                echo "移动可执行文件到目标目录"
                mv -f "$temp_dir/$beta_build_path/$SOFTWARE_NAME" "$TARGET_DIR/"
                chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
            else
                echo "警告: 在预期路径中未找到可执行文件"
            fi
            
            echo "移动其他测试版文件到目标目录"
            find "$temp_dir/$beta_build_path" -mindepth 1 -maxdepth 1 -type f -not -name "$SOFTWARE_NAME" -exec mv -f {} "$TARGET_DIR/" \;
            
            rm -rf "$temp_dir/$beta_build_path"
        else
            echo "警告: 未找到预期的测试版目录结构: $beta_build_path"
            find_result=$(find "$temp_dir" -name "$SOFTWARE_NAME" -type f | head -n 1)
            if [ -n "$find_result" ]; then
                echo "找到替代可执行文件: $find_result"
                mv -f "$find_result" "$TARGET_DIR/"
                chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
            else
                rm -f "$download_path"
                rm -rf "$temp_dir"
                handle_error 1 "未找到可执行文件，测试版安装失败"
            fi
        fi
    else
        echo "处理稳定版文件结构..."
        cp -rf "$temp_dir"/* "$TARGET_DIR/"
        if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
            chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
        fi
    fi
    
    rm -f "$download_path"
    rm -rf "$temp_dir"
    
    if [ ! -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        handle_error 1 "安装失败: 未找到可执行文件 $TARGET_DIR/$SOFTWARE_NAME"
    fi
    
    if [ "$USE_BETA" = true ]; then
        LATEST_VERSION="beta-$(date +%Y%m%d)"
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        echo "测试版信息已保存: $LATEST_VERSION"
    elif [ -n "$LATEST_VERSION" ]; then
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        echo "稳定版信息已保存: $LATEST_VERSION"
    fi
    
    echo "安装完成！"
    echo "===================="
    echo "$SOFTWARE_NAME 已安装到: $TARGET_DIR"
    if [ "$USE_BETA" = true ]; then
        echo "已安装测试版 (日期: $(date +%Y-%m-%d))"
    else
        echo "已安装稳定版: $LATEST_VERSION"
    fi
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
    
    if command -v ufw >/dev/null 2>&1; then
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
    elif command -v firewall-cmd >/dev/null 2>&1; then
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
    
    echo "端口 $PORT 已开放"
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
    select_version
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