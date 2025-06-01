#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
CLEWDR_DIR="$DIR/clewdr"
CONFIG="$CLEWDR_DIR/clewdr.toml"
ST_DIR="$DIR/SillyTavern"
SERVICE="/etc/systemd/system/clewdr.service"
PROXY="https://ghfast.top"
DL_BASE="https://github.com/Xerxes-2/clewdr/releases/latest/download"

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
        echo "检测到Termux环境，自动选择aarch64架构。"
        ARCH="aarch64"
        LIBC="android"
        return
    fi

    case "$(uname -m)" in
        x86_64|amd64) ARCH="x86_64";;
        aarch64|arm64) ARCH="aarch64";;
        *) err "不支持的架构";;
    esac

    if command -v ldd &>/dev/null && ldd --version | grep -qi 'glibc'; then
        GLIBC_VER=$(ldd --version | head -1 | grep -o '[0-9]\+\.[0-9]\+')
        [[ $(echo "$GLIBC_VER >= 2.38" | bc) -eq 1 ]] && LIBC="linux" || LIBC="musllinux"
    else
        LIBC="musllinux"
    fi
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

install_clewdr() {
    detect_arch_libc
    local proxy=$(use_proxy && echo "$PROXY" || echo "")
    local file="clewdr-${LIBC}-${ARCH}.zip"
    local url="${proxy}${DL_BASE}/$file"
    mkdir -p "$CLEWDR_DIR"
    curl -fL "$url" -o "$CLEWDR_DIR/$file" || err "下载失败"
    unzip -oq "$CLEWDR_DIR/$file" -d "$CLEWDR_DIR" || err "解压失败"
    chmod +x "$CLEWDR_DIR/clewdr"
    rm -f "$CLEWDR_DIR/$file"
    echo "ClewdR安装完成"
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

main_menu() {
    CLEWDR_VER=$(get_local_ver "$CLEWDR_DIR/clewdr")
    CLEWDR_LATEST=$(get_latest_ver "Xerxes-2/clewdr")
    ST_VER=$(get_st_ver)
    ST_LATEST=$(get_latest_ver "SillyTavern/SillyTavern")

    while true; do
        clear
        echo "====== ClewdR & SillyTavern 管理 ======"
        echo "ClewdR 当前版本: $CLEWDR_VER | 最新版: $CLEWDR_LATEST"
        echo "SillyTavern 当前版本: $ST_VER | 最新版: $ST_LATEST"
        echo "---------------------------------------"
        echo "1) 安装/更新 ClewdR"
        echo "2) 启动 ClewdR"
        echo "3) 编辑配置文件"
        echo "4) 开放公网IP"
        echo "5) 修改监听端口"
        echo "6) 创建 systemd 服务"
        echo ""
        echo "7) 安装/更新 SillyTavern"
        echo "8) 启动 SillyTavern"
        echo "0) 退出"
        read -rp "选择操作: " opt
        case "$opt" in
            1) check_deps; install_clewdr;;
            2) "$CLEWDR_DIR/clewdr";;
            3) edit_config;;
            4) set_public_ip;;
            5) set_port;;
            6) create_service;;
            7) check_deps; install_st;;
            8) (cd "$ST_DIR"; node server.js);;
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