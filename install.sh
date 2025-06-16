#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
CLEWDR_DIR="$DIR/clewdr"
CONFIG="$CLEWDR_DIR/clewdr.toml"
ST_DIR="$DIR/SillyTavern"
SERVICE="/etc/systemd/system/clewdr.service"
PROXY="https://ghfast.top"
DL_BASE="https://github.com/Xerxes-2/clewdr/releases/latest/download"
FB_DIR="$DIR/filebrowser"

err() { echo "错误: $1" >&2; exit "${2:-1}"; }

check_deps() {
    local deps=(curl unzip git npm node jq)
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null || err "未安装依赖: $dep"
    done
}

use_proxy() {
    local country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null)
    [[ "$country" == "CN" ]] && read -rp "检测到大陆IP，是否使用代理加速?(Y/n): " yn && [[ ! "$yn" =~ ^[Nn]$ ]]
}

detect_arch_libc() {
    if [[ "$PREFIX" == *"/com.termux"* ]]; then
        echo "检测到 Termux 环境"
        ARCH="aarch64"
        LIBC="android"
        return
    fi

    case "$(uname -m)" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        *) err "不支持的架构：$(uname -m)" ;;
    esac

    LIBC="musllinux"
    echo "检测到常规 Linux 环境"
}

get_latest_ver() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name
}

get_local_ver() {
    [ -x "$1" ] && "$1" -V 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "未安装"
}

get_st_ver() {
    [ -f "$ST_DIR/package.json" ] && jq -r .version "$ST_DIR/package.json" || echo "未安装"
}

get_fb_ver() {
    if command -v filebrowser >/dev/null 2>&1; then
        local version_output=$(filebrowser version 2>&1)
        local version=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        [ -n "$version" ] && echo "${version#v}" || echo "版本获取失败"
    else
        echo "未安装"
    fi
}

install_clewdr() {
    detect_arch_libc
    local proxy=$(use_proxy && echo "$PROXY")
    local file="clewdr-${LIBC}-${ARCH}.zip"
    local url="${proxy}${DL_BASE}/$file"
    mkdir -p "$CLEWDR_DIR"
    curl -fL "$url" -o "$CLEWDR_DIR/$file" || err "下载失败：$url"
    unzip -oq "$CLEWDR_DIR/$file" -d "$CLEWDR_DIR" || err "解压失败"
    chmod +x "$CLEWDR_DIR/clewdr"
    rm -f "$CLEWDR_DIR/$file"
    echo "ClewdR 安装/更新完成（${ARCH}/${LIBC}）"
}

install_st() {
    local repo="https://github.com/SillyTavern/SillyTavern"
    use_proxy && repo="$PROXY/$repo"
    [ -d "$ST_DIR/.git" ] && (cd "$ST_DIR"; git pull) || git clone --depth 1 --branch release "$repo" "$ST_DIR"
    (cd "$ST_DIR"; npm install) || err "npm依赖安装失败"
    echo "SillyTavern安装完成"
}

edit_config() {
    [ -f "$CONFIG" ] || "$CLEWDR_DIR/clewdr" && sleep 2
    command -v vim &>/dev/null && vim "$CONFIG" || nano "$CONFIG"
}

set_public_ip() {
    sed -i 's/127\.0\.0\.1/0.0.0.0/' "$CONFIG"
    echo "已开放公网访问"
}

set_port() {
    read -rp "请输入新端口[1-65535]: " port
    [[ "$port" =~ ^[0-9]+$ ]] && ((port > 0 && port < 65536)) || err "无效端口"
    sed -i -E "s/^(#?\s*port\s*=).*/\1 $port/" "$CONFIG" || echo "port = $port" >> "$CONFIG"
    echo "端口已修改为 $port"
}

create_service() {
    [ "$EUID" -ne 0 ] && err "需root权限"
    cat > "$SERVICE" <<EOF
[Unit]
Description=ClewdR Service
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$CLEWDR_DIR
ExecStart=$CLEWDR_DIR/clewdr
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo "服务已创建，可使用systemctl管理clewdr服务"
}

install_filebrowser() {
    echo "正在安装 filebrowser..."
    if ! curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash; then
        handle_error 1 "filebrowser 安装脚本执行失败。"
        return 1
    fi
    chmod +x "$FB_DIR"
    echo "filebrowser 安装成功: $FB_DIR"
}

start_filebrowser() {
    echo -e "\e]0;Filebrowser\a"
    echo "访问地址: http://<127.0.0.1或服务器IP>:8080"
    echo "初始用户名: admin"
    echo "初始密码: admin"
    "filebrowser" -a 0.0.0.0 -p 8080
}


main_menu() {
    CLEWDR_VER=$(get_local_ver "$CLEWDR_DIR/clewdr")
    CLEWDR_LATEST=$(get_latest_ver "Xerxes-2/clewdr")
    ST_VER=$(get_st_ver)
    ST_LATEST=$(get_latest_ver "SillyTavern/SillyTavern")
    FB_VER=$(get_fb_ver)
    FB_LATEST=$(get_latest_ver "filebrowser/filebrowser")
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    GRAY='\033[0;37m'
    NC='\033[0m'
    
    while true; do
        clear
        echo -e "${CYAN}============================================${NC}"
        echo -e "${WHITE}        ClewdR & SillyTavern 管理工具        ${NC}"
        echo -e "${CYAN}============================================${NC}"
        echo -e "${GRAY}ClewdR 版本:      ${GREEN}$CLEWDR_VER${NC} ${GRAY}→${NC} ${YELLOW}$CLEWDR_LATEST${NC}"
        echo -e "${GRAY}SillyTavern 版本: ${GREEN}$ST_VER${NC} ${GRAY}→${NC} ${YELLOW}$ST_LATEST${NC}"
        echo -e "${GRAY}FileBrowser 版本: ${GREEN}$FB_VER${NC} ${GRAY}→${NC} ${YELLOW}$FB_LATEST${NC}"
        echo -e "${CYAN}--------------------------------------------${NC}"
        echo -e "${BLUE}[ClewdR 管理]${NC}"
        echo -e "  ${GREEN}1)${NC} 安装/更新 ClewdR"
        echo -e "  ${GREEN}2)${NC} 启动 ClewdR"
        echo -e "  ${GREEN}3)${NC} 编辑配置文件"
        echo -e "  ${GREEN}4)${NC} 开放公网IP"
        echo -e "  ${GREEN}5)${NC} 修改监听端口"
        echo -e "  ${GREEN}6)${NC} 创建 systemd 服务"
        echo ""
        echo -e "${BLUE}[SillyTavern 管理]${NC}"
        echo -e "  ${GREEN}7)${NC} 安装/更新 SillyTavern"
        echo -e "  ${GREEN}8)${NC} 启动 SillyTavern"
        echo ""
        echo -e "${BLUE}[FileBrowser 管理]${NC}"
        echo -e "  ${GREEN}9)${NC}  安装/更新 FileBrowser"
        echo -e "  ${GREEN}10)${NC} 启动 FileBrowser"
        echo ""
        echo -e "  ${RED}0)${NC} 退出"
        echo -e "${CYAN}============================================${NC}"
        read -rp "请选择操作 [0-10]:" opt
        case "$opt" in
            1) check_deps; install_clewdr;;
            2) echo -e "\e]0;ClewdR\a";"$CLEWDR_DIR/clewdr";;
            3) edit_config;;
            4) set_public_ip;;
            5) set_port;;
            6) create_service;;
            7) check_deps; install_st;;
            8) (cd "$ST_DIR"; node server.js);;
            9) install_filebrowser;;
            10) start_filebrowser;;
            0) exit;;
            *) echo "无效选项";;
        esac
        read -n1 -rp "按任意键返回菜单"
    done
}

case "$1" in
    -h) echo "用法: $0 [-h 帮助|-ic 安装clewdr|-is 安装酒馆|-sc 启动clewdr|-ss 启动酒馆]";;
    -ic) check_deps; install_clewdr;;
    -is) check_deps; install_st;;
    -sc) "$CLEWDR_DIR/clewdr";;
    -ss) (cd "$ST_DIR"; node server.js);;
    *) main_menu;;
esac