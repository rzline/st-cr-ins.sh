#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_FILE="${SCRIPT_DIR}/clewdr/clewdr.toml"
COOKIES_FILE="${SCRIPT_DIR}/clewdr/cookies.txt"
GITHUB_PROXY="https://ghfast.top"
DOWNLOAD_BASE="https://github.com/Xerxes-2/clewdr/releases/latest/download"
SILLY_TAVERN_DIR="${SCRIPT_DIR}/SillyTavern"
SILLY_TAVERN_REPO="https://github.com/SillyTavern/SillyTavern"

handle_error() {
    echo "错误：$1" >&2
    return "${2:-1}"
}

check_dependencies() {
    local deps=(curl unzip)
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || { handle_error "缺少 '$dep'"; return 1; }
    done
    return 0
}

get_proxy_choice() {
    local country
    country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null)
    if [ "$country" == "CN" ]; then
        echo "检测到中国大陆 IP，建议使用代理下载。"
        read -rp "是否禁用 GitHub 代理？(y/N): " disable_proxy
        [[ "$disable_proxy" =~ ^[Yy]$ ]] && echo "no" || echo "yes"
    else
        echo "检测到非中国大陆 IP，直连 GitHub。"
        echo "no"
    fi
}

detect_system() {
    local is_termux=false
    USE_GLIBC_BINARY=false

    if [[ -n "$PREFIX" && "$PREFIX" == *"/com.termux"* ]]; then
        is_termux=true
        echo "检测到 Termux 环境。"
    elif command -v ldd >/dev/null 2>&1; then
        if ldd --version 2>&1 | grep -qi 'musl'; then
            echo "检测到 MUSL 环境，使用 musl 二进制文件。"
        else
            echo "检测到 glibc 环境。"
            local detected_version required_version="2.38"
            detected_version=$(ldd --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
            
            if [[ -n "$detected_version" ]] && [[ "$detected_version" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
                local glibc_major=${BASH_REMATCH[1]} glibc_minor=${BASH_REMATCH[2]}
                local req_major=2 req_minor=38
                echo "检测到 glibc 版本: $detected_version"
                
                if (( glibc_major > req_major )) || { (( glibc_major == req_major )) && (( glibc_minor >= req_minor )); }; then
                    echo "glibc 版本满足要求，使用 glibc 二进制文件。"
                    USE_GLIBC_BINARY=true
                else
                    echo "glibc 版本过低，使用 musl 二进制文件。"
                fi
            else
                echo "无法确定 glibc 版本，使用 musl 二进制文件以保证兼容性。"
            fi
        fi
    else
        echo "无法检测 libc 类型，使用 musl 二进制文件以保证兼容性。"
    fi

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        armv7l|armv8l) handle_error "暂不支持32位 ARM ($arch)" && return 1 ;;
        *) handle_error "不支持的架构：$arch" && return 1 ;;
    esac
    
    echo "系统架构: $arch"
    $is_termux && [ "$arch" != "aarch64" ] && { handle_error "Termux环境仅支持 aarch64"; return 1; }

    ARCH="$arch"
    TERMUX=$is_termux
    return 0
}

check_version() {
    local local_ver=""
    if [ -x "${SCRIPT_DIR}/clewdr/clewdr" ]; then
        local_ver=$("${SCRIPT_DIR}/clewdr/clewdr" -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        echo "当前已安装的 clewdr 版本：$local_ver"
    else
        echo "未检测到 clewdr，视为首次安装。"
    fi

    local latest_info remote_ver
    latest_info=$(curl -s --connect-timeout 10 "https://api.github.com/repos/Xerxes-2/clewdr/releases/latest")
    if [ -z "$latest_info" ]; then
        echo "获取最新版本信息失败。"
        if [ -n "$local_ver" ]; then
            read -rp "是否强制更新？(y/N): " force
            [[ "$force" =~ ^[Yy]$ ]] || return 1
        fi
        remote_ver="unknown"
    else
        if command -v jq &>/dev/null; then
            remote_ver=$(echo "$latest_info" | jq -r .tag_name)
        else
            remote_ver=$(echo "$latest_info" | grep -oE '"tag_name": *"([^"]+)"' | head -n1 | cut -d'"' -f4)
        fi
        echo "最新版本：$remote_ver"
    fi
    
    if [ "$local_ver" = "$remote_ver" ] && [ -n "$local_ver" ]; then
        read -rp "当前已是最新版本，是否强制重装？(y/N): " reinstall
        [[ "$reinstall" =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

setup_download_url() {
    local proxy_choice
    proxy_choice=$(get_proxy_choice)
    if [ "$proxy_choice" == "yes" ]; then
        URL_PREFIX="${GITHUB_PROXY}${DOWNLOAD_BASE}"
        echo "使用代理地址: ${GITHUB_PROXY}"
    else
        URL_PREFIX="$DOWNLOAD_BASE"
    fi

    if $TERMUX; then
        FILENAME="clewdr-android-${ARCH}.zip"
        echo "为 Termux 环境选择 Android 版本。"
    elif [ "$USE_GLIBC_BINARY" = true ]; then
        FILENAME="clewdr-linux-${ARCH}.zip"
        echo "选择 glibc 版本。"
    else
        FILENAME="clewdr-musllinux-${ARCH}.zip"
        echo "选择 musl 版本。"
    fi

    [ -z "$FILENAME" ] && { handle_error "无法确定下载文件名"; return 1; }
    echo "下载文件名: $FILENAME"
    return 0
}

download_and_install() {
    mkdir -p "$SCRIPT_DIR/clewdr" || { handle_error "创建目标目录失败"; return 1; }
    local download_url="${URL_PREFIX}/${FILENAME}"
    local download_path="${SCRIPT_DIR}/clewdr/${FILENAME}"
    echo "下载地址: $download_url"

    if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$download_url" -o "$download_path"; then
        if [ -s "$download_path" ]; then
            echo "下载成功。"
        else
            rm -f "$download_path"
            handle_error "下载的文件为空"; return 1
        fi
    else
        rm -f "$download_path"
        handle_error "下载失败"; return 1
    fi

    if unzip -oq "$download_path" -d "$SCRIPT_DIR/clewdr"; then
        rm -f "$download_path"
        echo "解压成功。"
    else
        rm -f "$download_path"
        handle_error "解压失败"; return 1
    fi

    [ -f "${SCRIPT_DIR}/clewdr/clewdr" ] && chmod +x "${SCRIPT_DIR}/clewdr/clewdr"
    echo "clewdr 安装/更新完成于目录：$SCRIPT_DIR/clewdr"
}

install_sillytavern() {
    for dep in git npm; do
        command -v "$dep" &>/dev/null || { handle_error "缺少 '$dep'"; return 1; }
    done

    local use_proxy="no"
    local country
    country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null)
    if [ "$country" == "CN" ]; then
        read -rp "检测到中国大陆 IP，是否禁用 Git 代理？(y/N): " disable
        [[ "$disable" =~ ^[Yy]$ ]] || { use_proxy="yes"; SILLY_TAVERN_REPO="${GITHUB_PROXY}/${SILLY_TAVERN_REPO}"; }
    fi

    if [ -d "$SILLY_TAVERN_DIR" ]; then
        if [ -d "$SILLY_TAVERN_DIR/.git" ]; then
            echo "更新现有的 SillyTavern..."
            cd "$SILLY_TAVERN_DIR" || return 1
            git pull || { echo "git pull 失败"; cd "$SCRIPT_DIR"; return 1; }
        else
            read -rp "目录存在但非 Git 仓库，是否清理后重新克隆？(y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || return 1
            rm -rf "$SILLY_TAVERN_DIR"
            git clone --depth 1 --branch release "$SILLY_TAVERN_REPO" "$SILLY_TAVERN_DIR" || return 1
        fi
    else
        echo "克隆 SillyTavern..."
        git clone --depth 1 --branch release "$SILLY_TAVERN_REPO" "$SILLY_TAVERN_DIR" || return 1
    fi

    cd "$SILLY_TAVERN_DIR" || return 1
    echo "安装依赖..."
    npm install || { echo "npm install 失败"; cd "$SCRIPT_DIR"; return 1; }
    cd "$SCRIPT_DIR"
    echo "SillyTavern 安装/更新成功。"
}

add_cookies() {
    rm -f "$COOKIES_FILE" 2>/dev/null
    touch "$COOKIES_FILE" || { handle_error "无法创建 $COOKIES_FILE"; return 1; }
    echo "请粘贴 Cookie 内容（一行一个，包含 sessionKey=... ），输入完成后按 Ctrl+D 结束："
    local count=0
    while IFS= read -r line; do
        local cookie_line=$(echo "$line" | grep -E -o 'sessionKey=(sk-ant-sid[a-zA-Z0-9_-]+|[a-zA-Z0-9+/_-]{100,})')
        if [ -n "$cookie_line" ]; then
            echo "$cookie_line" >> "$COOKIES_FILE"
            echo "已缓存有效 Cookie: $cookie_line"
            count=$((count+1))
        else
            [ -n "$line" ] && echo "忽略无效输入: $line"
        fi
    done
    echo "共缓存 $count 个有效 Cookie 到 $COOKIES_FILE"
    
    if [ $count -gt 0 ] && [ -x "${SCRIPT_DIR}/clewdr/clewdr" ]; then
        echo "现在启动 clewdr..."
        cd "$SCRIPT_DIR/clewdr" && ./clewdr -f cookies.txt
    fi
}

modify_port() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件不存在，请先运行一次 clewdr 生成默认配置。"
        return 1
    fi
    
    local cur_port
    cur_port=$(grep -E '^\s*port\s*=' "$CONFIG_FILE" | sed -E 's/^\s*port\s*=\s*([0-9]+).*/\1/' | head -n1)
    echo "当前端口: ${cur_port:-未设置 (默认 8080)}"
    
    read -rp "请输入新的监听端口 [1-65535]: " new_port
    if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
        if grep -qE '^\s*#?\s*port\s*=' "$CONFIG_FILE"; then
            sed -i.bak -E "s/^\s*#?\s*(port\s*=\s*)[0-9]+/\1$new_port/" "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
        else
            echo -e "\nport = $new_port" >> "$CONFIG_FILE"
        fi
        echo "端口已修改为 $new_port"
    else
        echo "端口号无效，必须是 1-65535 之间的数字。"
    fi
}

main_menu() {
    local local_ver="未安装"
    if [ -x "${SCRIPT_DIR}/clewdr/clewdr" ]; then
        local_ver=$("${SCRIPT_DIR}/clewdr/clewdr" -V 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    fi

    local st_status="未安装"
    [ -d "$SILLY_TAVERN_DIR" ] && st_status="已安装"

    clear
    echo "========================================="
    echo "       ClewdR & SillyTavern 管理"
    echo "========================================="
    echo "ClewdR 版本: $local_ver"
    echo "SillyTavern 状态: $st_status"
    echo "-----------------------------------------"
    echo " 1) 启动 ClewdR"
    echo " 2) 安装/更新 ClewdR"
    echo " 3) 添加 Cookie"
    echo " 4) 查看配置文件"
    echo " 5) 编辑配置文件"
    echo " 6) 修改监听端口"
    echo " 7) 启动 SillyTavern"
    echo " 8) 安装/更新 SillyTavern"
    echo " 0) 退出"
    echo "========================================="
    read -n1 -rp "请输入选项 [0-8]: " opt
    echo

    case $opt in
        1)
            echo "启动 ClewdR..."
            if [ -x "${SCRIPT_DIR}/clewdr/clewdr" ]; then
                cd "$SCRIPT_DIR/clewdr" && ./clewdr
            else
                echo "错误：ClewdR 未安装，请先选择选项 2 安装。"
            fi
            ;;
        2)
            echo "安装/更新 ClewdR..."
            check_dependencies || return 1
            detect_system || return 1
            check_version || return 1
            setup_download_url || return 1
            download_and_install || return 1
            ;;
        3)
            add_cookies
            ;;
        4)
            echo "配置文件内容："
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo "配置文件不存在。首次启动 clewdr 时会自动创建。"
            fi
            ;;
        5)
            if [ -f "$CONFIG_FILE" ]; then
                if command -v vim &>/dev/null; then
                    vim "$CONFIG_FILE"
                elif command -v nano &>/dev/null; then
                    nano "$CONFIG_FILE"
                else
                    echo "未找到 vim 或 nano 编辑器。"
                fi
            else
                echo "配置文件不存在。首次启动 clewdr 时会自动创建。"
            fi
            ;;
        6)
            modify_port
            ;;
        7)
            echo "启动 SillyTavern..."
            if [ -f "${SILLY_TAVERN_DIR}/server.js" ]; then
                if command -v node &>/dev/null; then
                    cd "$SILLY_TAVERN_DIR" && node server.js
                else
                    echo "错误：缺少 node 命令。"
                fi
            else
                echo "错误：SillyTavern 未安装，请先选择选项 8 安装。"
            fi
            ;;
        8)
            echo "安装/更新 SillyTavern..."
            install_sillytavern || echo "SillyTavern 安装/更新失败。"
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项。"
            ;;
    esac
    echo -e "\n按任意键返回主菜单..."
    read -n1 -s
    return 0
}

show_help() {
    echo "ClewdR & SillyTavern 管理脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -inc, --install-clewdr        自动安装/更新 ClewdR"
    echo "  -ins, --install-sillytavern   自动安装/更新 SillyTavern"
    echo "  -sc, --start-clewdr          启动 ClewdR"
    echo "  -ss, --start-sillytravern      启动 SillyTravern"
}

# 处理命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -inc|--install-clewdr)
        echo "自动安装/更新 ClewdR..."
        check_dependencies || exit 1
        detect_system || exit 1
        check_version || exit 1
        setup_download_url || exit 1
        download_and_install || exit 1
        exit 0
        ;;
    -ins|--install-sillytavern)
        echo "自动安装/更新 SillyTavern..."
        install_sillytavern || exit 1
        exit 0
        ;;
    -sc|--start-clewdr)
        echo "启动 ClewdR..."
        if [ -x "${SCRIPT_DIR}/clewdr/clewdr" ]; then
            cd "$SCRIPT_DIR/clewdr" && ./clewdr
        else
            echo "错误：ClewdR 未安装"
            exit 1
        fi
        exit 0
        ;;
    -ss|--start-sillytravern)
        echo "启动 SillyTavern..."
        if [ -f "${SILLY_TAVERN_DIR}/server.js" ]; then
            if command -v node &>/dev/null; then
                cd "$SILLY_TAVERN_DIR" && node server.js
            else
                echo "错误：缺少 node 命令。"
            fi
        else
            echo "错误：SillyTavern 未安装，请先选择选项 8 安装。"
        fi
        ;;
    "")
        # 无参数，启动交互式菜单
        while true; do
            main_menu || break
        done
        ;;
    *)
        echo "错误：未知参数 '$1'"
        echo "使用 '$0 --help' 查看帮助信息"
        exit 1
        ;;
esac

echo "脚本执行完毕。"
exit 0