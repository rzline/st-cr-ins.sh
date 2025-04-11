#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/clewdr"
CONFIG_FILE="${TARGET_DIR}/config.toml"
COOKIES_FILE="${SCRIPT_DIR}/cookies.txt"
GITHUB_PROXY="https://ghfast.top"
GITHUB_REPO="Xerxes-2/clewdr"
DOWNLOAD_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
SILLY_TAVERN_DIR="${SCRIPT_DIR}/SillyTavern"
SILLY_TAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git"

if [ "$1" == "cookies.txt" ]; then
    if [ ! -f "$COOKIES_FILE" ]; then
        echo "错误：未找到 $COOKIES_FILE 文件。"
        exit 1
    fi
    if [ -x "${TARGET_DIR}/clewdr" ]; then
        echo "使用 $COOKIES_FILE 启动 clewdr..."
        cd "$TARGET_DIR" && ./clewdr ../cookies.txt || echo "启动 clewdr 失败。"
        cd "$SCRIPT_DIR"
    else
        echo "错误：未找到 clewdr 可执行文件。请先运行脚本进行安装或更新。"
    fi
    exit 0
fi

handle_error() {
    echo "错误：$2" >&2
    echo "操作中止。" >&2
    return "${1:-1}"
}

check_dependencies() {
    local deps=(curl unzip)
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || { echo "错误：缺少 '$dep'" >&2; return 1; }
    done
    return 0
}

get_proxy_choice() {
    local country
    country=$(curl -s --connect-timeout 5 ipinfo.io/country)
    if [ "$country" == "CN" ]; then
        echo "检测到中国大陆 IP ($country)，建议使用代理下载。"
        read -rp "是否禁用 GitHub 代理？(y/N): " disable_proxy
        [[ "$disable_proxy" =~ ^[Yy]$ ]] && echo "no" || echo "yes"
    else
        echo "检测到非中国大陆 IP ($country)，直连 GitHub。"
        echo "no"
    fi
}

detect_system() {
    local is_termux=false is_musl=false
    if [[ -n "$PREFIX" && "$PREFIX" == *"/com.termux"* ]]; then
        is_termux=true
        echo "检测到 Termux 环境。"
    elif command -v ldd >/dev/null 2>&1; then
        if ldd --version 2>&1 | grep -qi 'musl' || (command -v readelf &>/dev/null && readelf -l /bin/sh 2>/dev/null | grep -q 'musl'); then
            is_musl=true
            echo "检测到 MUSL 环境。"
        else
            echo "检测到 glibc 环境。"
        fi
    else
        echo "警告：无法检测 libc 类型，假定为 glibc。"
    fi

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        armv7l|armv8l) handle_error 1 "暂不支持32位 ARM ($arch)" && return 1 ;;
        *) handle_error 1 "不支持的架构：$arch" && return 1 ;;
    esac
    echo "系统架构: $arch"
    $is_termux && [ "$arch" != "aarch64" ] && { handle_error 1 "Termux环境仅支持 aarch64"; return 1; }
    ARCH="$arch"
    TERMUX=$is_termux
    MUSL=$is_musl
    return 0
}

check_version() {
    local local_ver=""
    if [ -x "${TARGET_DIR}/clewdr" ]; then
        local_ver=$("${TARGET_DIR}/clewdr" -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        echo "当前已安装的 clewdr 版本：$local_ver"
    else
        echo "未检测到 clewdr，视为首次安装。"
    fi

    local latest_info remote_ver
    latest_info=$(curl -s --connect-timeout 10 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo "获取最新版本信息失败。"
        if [ -n "$local_ver" ]; then
            read -rp "是否强制更新？(y/N): " force
            [[ "$force" =~ ^[Yy]$ ]] || return 1
            remote_ver="unknown"
        else
            remote_ver="unknown"
        fi
    else
        if command -v jq &>/dev/null; then
            remote_ver=$(echo "$latest_info" | jq -r .tag_name)
        else
            remote_ver=$(echo "$latest_info" | grep -oE '"tag_name": *"([^"]+)"' | head -n1 | cut -d'"' -f4)
        fi
    fi
    [ -z "$remote_ver" ] && { echo "无法解析最新版本信息"; return 1; }
    echo "最新版本：$remote_ver"
    if [ "$local_ver" = "$remote_ver" ]; then
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
    elif $MUSL; then
        FILENAME="clewdr-musllinux-${ARCH}.zip"
    else
        echo "请选择二进制文件类型："
        echo "  1) glibc 版本"
        echo "  2) musl 版本"
        read -rp "输入选项 [1-2] (默认 1): " choice
        if [ "${choice:-1}" -eq 2 ]; then
            FILENAME="clewdr-musllinux-${ARCH}.zip"
        else
            FILENAME="clewdr-linux-${ARCH}.zip"
        fi
    fi
    [ -z "$FILENAME" ] && { handle_error 1 "无法确定下载文件名"; return 1; }
    echo "下载文件名: $FILENAME"
    return 0
}

download_and_install() {
    [ -z "$URL_PREFIX" ] && { handle_error 1 "下载 URL 前缀未配置"; return 1; }
    [ -z "$FILENAME" ] && { handle_error 1 "下载文件名未配置"; return 1; }

    mkdir -p "$TARGET_DIR" || { handle_error 1 "创建目标目录失败: ${TARGET_DIR}"; return 1; }
    local download_url="${URL_PREFIX}/${FILENAME}"
    local download_path="${TARGET_DIR}/${FILENAME}"
    echo "下载地址: $download_url"
    echo "保存到: $download_path"

    local max=3 count=0 wait_time=5
    while [ $count -lt $max ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$download_url" -o "$download_path"; then
            [ -s "$download_path" ] && { echo "下载成功。"; break; }
        fi
        rm -f "$download_path"
        ((count++))
        [ $count -lt $max ] && { echo "等待 $wait_time 秒重试..."; sleep $wait_time; wait_time=$((wait_time+5)); }
    done
    [ $count -eq $max ] && { handle_error 1 "下载失败"; return 1; }

    if unzip -oq "$download_path" -d "$TARGET_DIR"; then
        rm -f "$download_path"
        echo "解压成功。"
    else
        rm -f "$download_path"
        handle_error 1 "解压失败"; return 1
    fi

    [ -f "${TARGET_DIR}/clewdr" ] && chmod +x "${TARGET_DIR}/clewdr" || echo "警告：找不到 clewdr 可执行文件"
    echo "clewdr 安装/更新完成于目录：$TARGET_DIR"
}

install_sillytavern() {
    for dep in git npm curl; do
        command -v "$dep" &>/dev/null || { echo "错误：缺少 '$dep'" >&2; return 1; }
    done

    local use_proxy="no"
    local country
    country=$(curl -s --connect-timeout 5 ipinfo.io/country)
    if [ "$country" == "CN" ]; then
        read -rp "检测到中国大陆 IP，是否禁用 Git 代理？(y/N): " disable
        [[ "$disable" =~ ^[Yy]$ ]] || { use_proxy="yes"; SILLY_TAVERN_REPO="${GITHUB_PROXY}/${SILLY_TAVERN_REPO}"; }
    fi

    if [ -d "$SILLY_TAVERN_DIR" ]; then
        if [ -d "$SILLY_TAVERN_DIR/.git" ]; then
            cd "$SILLY_TAVERN_DIR" || return 1
            git diff --quiet && git diff --cached --quiet || git stash push -m "stash for update"
            git pull || { echo "git pull 失败"; cd "$SCRIPT_DIR"; return 1; }
            cd "$SCRIPT_DIR"
        else
            read -rp "目录存在但非 Git 仓库，是否清理后重新克隆？(y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || return 1
            rm -rf "$SILLY_TAVERN_DIR"
            git clone --depth 1 --branch release "$SILLY_TAVERN_REPO" "$SILLY_TAVERN_DIR" || return 1
        fi
    else
        git clone --depth 1 --branch release "$SILLY_TAVERN_REPO" "$SILLY_TAVERN_DIR" || return 1
    fi

    cd "$SILLY_TAVERN_DIR" || return 1
    [ -f "package.json" ] || { echo "缺少 package.json"; cd "$SCRIPT_DIR"; return 1; }
    local npm_cmd="npm install"
    [ "$use_proxy" == "yes" ] && npm_cmd="npm install --proxy=${GITHUB_PROXY} --https-proxy=${GITHUB_PROXY}"
    $npm_cmd || { echo "npm install 失败"; cd "$SCRIPT_DIR"; return 1; }
    cd "$SCRIPT_DIR"
    echo "SillyTavern 安装/更新成功于目录：$SILLY_TAVERN_DIR"
}

main_menu() {
    local local_ver="未安装"
    if [ -x "${TARGET_DIR}/clewdr" ]; then
        local_ver=$("${TARGET_DIR}/clewdr" -V 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    fi

    local st_status="未安装"
    [ -d "$SILLY_TAVERN_DIR" ] && { [ -d "$SILLY_TAVERN_DIR/.git" ] && st_status="已安装 (Git)" || st_status="已安装"; }

    clear
    echo "========================================="
    echo "       ClewdR & SillyTavern 管理"
    echo "========================================="
    echo "clewdr 版本: $local_ver"
    echo "SillyTavern 状态: $st_status"
    echo "-----------------------------------------"
    echo "操作选项:"
    echo " 1) 启动ClewdR"
    echo " 2) 安装/更新ClewdR"
    echo " 3) 查看配置文件"
    echo " 4) 编辑配置文件"
    echo " 5) 添加Cookie"
    echo " 6) 修改监听端口"
    echo " 7) 启动SillyTavern"
    echo " 8) 安装/更新SillyTavern"
    echo " 0) 退出"
    echo "========================================="
    read -n1 -rp "请输入选项 [0-8]: " opt
    echo

    case $opt in
        1)
            echo "启动 ClewdR (默认配置)..."
            if [ -x "${TARGET_DIR}/clewdr" ]; then
                cd "$TARGET_DIR" && ./clewdr && cd "$SCRIPT_DIR" || echo "启动 clewdr 失败。"
            else
                echo "错误：未找到可执行文件，请先安装更新。"
            fi
            ;;
        2)
            check_dependencies || return 1
            detect_system || return 1
            check_version || return 1
            setup_download_url || return 1
            download_and_install || return 1
            ;;
        3)
            echo "配置文件内容 (${CONFIG_FILE})："
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                 echo "配置文件不存在。当使用 cookies.txt 首次启动或无配置文件启动时，clewdr 会自动创建。"
            fi
            ;;
        4)
            if [ -f "$CONFIG_FILE" ]; then
                command -v vim &>/dev/null && vim "$CONFIG_FILE" || { command -v nano &>/dev/null && nano "$CONFIG_FILE" || echo "未找到 vim 或 nano 编辑器。"; }
            else
                 echo "配置文件不存在。当使用 cookies.txt 首次启动或无配置文件启动时，clewdr 会自动创建。"
            fi
            ;;
        5)
            rm -f "$COOKIES_FILE" 2>/dev/null
            touch "$COOKIES_FILE" || { echo "错误：无法创建 $COOKIES_FILE"; break; }
            echo "请粘贴 Cookie 内容（一行一个，包含 sessionKey=... ），输入完成后按 Ctrl+D 结束："
            count=0
            while IFS= read -r line; do
                cookie_line=$(echo "$line" | grep -E -o 'sessionKey=(sk-ant-sid[a-zA-Z0-9_-]+|[a-zA-Z0-9+/_-]{100,})')
                if [ -n "$cookie_line" ]; then
                    echo "$cookie_line" >> "$COOKIES_FILE"
                    echo "已缓存有效 Cookie 行: $cookie_line"
                    count=$((count+1))
                else
                    [ -n "$line" ] && echo "忽略无效输入行: $line"
                fi
            done
            echo "-----------------------------------------"
            echo "共缓存 $count 个有效 Cookie 到 $COOKIES_FILE"

            if [ -x "${TARGET_DIR}/clewdr" ]; then
                if [ -s "$COOKIES_FILE" ]; then
                    echo "现在尝试使用 $COOKIES_FILE 启动 clewdr..."
                    echo "clewdr 会读取此文件并自动处理配置。"
                    cd "$TARGET_DIR" && ./clewdr ../cookies.txt && cd "$SCRIPT_DIR" || echo "启动 clewdr 失败。"
                else
                    echo "未缓存任何有效 Cookie，未启动 clewdr。"
                    rm -f "$COOKIES_FILE"
                fi
            else
                echo "错误：未找到 clewdr 可执行文件。Cookie 已保存至 $COOKIES_FILE，请先安装或更新 clewdr 后手动执行："
                echo "cd ${TARGET_DIR} && ./clewdr ../cookies.txt"
            fi
            ;;
        6)
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "错误：配置文件 ${CONFIG_FILE} 不存在。"
                echo "请先至少运行一次 clewdr (例如通过选项5添加Cookie并启动，或直接启动) 以生成默认配置文件。"
            else
                local cur_port
                cur_port=$(grep -E '^\s*port\s*=' "$CONFIG_FILE" | sed -E 's/^\s*port\s*=\s*([0-9]+).*/\1/' | head -n1)
                echo "当前配置文件中的端口: ${cur_port:-未设置 (将使用默认值 8080)}"
                read -rp "是否修改配置文件中的端口设置？(y/N): " mod
                if [[ "$mod" =~ ^[Yy]$ ]]; then
                    read -rp "请输入新的监听端口 [1-65535]: " np
                    if [[ "$np" =~ ^[0-9]+$ ]] && [ "$np" -ge 1 ] && [ "$np" -le 65535 ]; then
                        if grep -qE '^\s*#?\s*port\s*=' "$CONFIG_FILE"; then
                            sed -i.bak -E "s/^\s*#?\s*(port\s*=\s*)[0-9]+/\1$np/" "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
                        else
                            echo -e "\nport = $np" >> "$CONFIG_FILE"
                        fi
                        echo "端口已在配置文件 ${CONFIG_FILE} 中修改为 $np。"
                        echo "下次启动 clewdr 时将生效 (若不使用 cookies.txt 启动)。"
                    else
                        echo "输入无效，端口号必须是 1 到 65535 之间的数字。"
                    fi
                fi
            fi
            ;;
        7)
            echo "启动 SillyTavern..."
            if [ -f "${SILLY_TAVERN_DIR}/server.js" ]; then
                command -v node &>/dev/null || { echo "错误：缺少 node 命令。"; break; }
                cd "$SILLY_TAVERN_DIR" && node server.js && cd "$SCRIPT_DIR" || echo "启动 SillyTavern 失败。"
            else
                echo "错误：SillyTavern 启动脚本 (${SILLY_TAVERN_DIR}/server.js) 不存在。"
            fi
            ;;
        8)
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

while true; do
    main_menu || break
done

echo "脚本执行完毕。"
exit 0
