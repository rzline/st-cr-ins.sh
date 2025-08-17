#!/bin/bash

# 配置常量
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEWDR_DIR="$SCRIPT_DIR/clewdr"
ST_DIR="$SCRIPT_DIR/SillyTavern"
CONFIG="$CLEWDR_DIR/clewdr.toml"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 日志输出函数
log() {
    local level=$1
    shift
    local -A colors=(
        ["INFO"]="$BLUE" 
        ["SUCCESS"]="$GREEN" 
        ["WARN"]="$YELLOW" 
        ["ERROR"]="$RED"
    )
    echo -e "${colors[$level]}[$level]$NC $*" >&2
}

# 错误退出函数
die() { 
    log ERROR "$1"
    exit "${2:-1}"
}

# 检查系统依赖
check_deps() {
    log INFO "检查系统依赖..."
    local missing=()
    
    for dep in curl git npm unzip node; do
        if ! command -v "$dep" >/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -ne 0 ]]; then
        die "缺少以下依赖: ${missing[*]}"
    fi
    
    log SUCCESS "系统依赖检查完成"
}

# 检测系统架构并返回旧版格式名称
detect_arch() {
    if [[ "${PREFIX:-}" == *termux* ]]; then
        echo "android-aarch64"
    else
        case "$(uname -m)" in
            x86_64|amd64) 
                echo "musllinux-x86_64" 
                ;;
            aarch64|arm64) 
                echo "musllinux-aarch64" 
                ;;
            *) 
                die "不支持的系统架构: $(uname -m)" 
                ;;
        esac
    fi
}

# 获取GitHub最新版本
get_latest_release() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | 
        grep '"tag_name"' | 
        cut -d'"' -f4
}

# 安装 ClewdR
install_clewdr() {
    log INFO "开始安装 ClewdR..."
    
    # 获取最新版本号
    local version
    version=$(get_latest_release "Xerxes-2/clewdr")
    if [[ -z "$version" ]]; then
        die "无法获取 ClewdR 最新版本信息"
    fi
    
    # 检测目标平台
    local arch
    arch=$(detect_arch)
    
    log INFO "版本: $version"
    log INFO "目标平台: $arch"
    
    # 创建安装目录
    mkdir -p "$CLEWDR_DIR"
    cd "$CLEWDR_DIR"
    
    # 下载对应架构的文件
    local download_url="https://github.com/Xerxes-2/clewdr/releases/download/${version}/clewdr-${arch}.zip"
    log INFO "下载: clewdr-${arch}.zip"
    
    if curl -L --fail "$download_url" -o clewdr.zip 2>/dev/null; then
        if unzip -t clewdr.zip &>/dev/null; then
            log SUCCESS "下载成功"
        else
            log ERROR "下载的文件无效"
            rm -f clewdr.zip
            die "下载的文件损坏，请重试"
        fi
    else
        die "下载失败。请检查网络连接或手动下载 ClewdR"
    fi
    
    log INFO "解压安装包..."
    if ! unzip -o clewdr.zip; then
        die "解压失败"
    fi
    
    rm clewdr.zip
    
    log SUCCESS "ClewdR 安装完成 (版本: $version, 平台: $arch)"
}

# 安装 SillyTavern
install_st() {
    log INFO "开始安装 SillyTavern..."
    
    if [[ -d "$ST_DIR/.git" ]]; then
        log INFO "检测到现有安装，正在更新..."
        (
            cd "$ST_DIR" && 
            git pull
        ) || die "SillyTavern 更新失败"
    else
        log INFO "克隆 SillyTavern 仓库..."
        git clone \
            --depth 1 \
            --branch release \
            "https://github.com/SillyTavern/SillyTavern" \
            "$ST_DIR" || die "SillyTavern 克隆失败"
    fi
    
    log INFO "安装 Node.js 依赖包..."
    (
        cd "$ST_DIR" && 
        npm install --omit=dev
    ) || die "SillyTavern 依赖安装失败"
    
    log SUCCESS "SillyTavern 安装完成"
}

# 启动服务
start_service() {
    local service_name=$1
    local service_dir=$2
    local service_cmd=$3
    
    log INFO "启动 $service_name..."
    
    if [[ ! -d "$service_dir" ]]; then
        die "$service_name 未安装，请先安装"
    fi
    
    # 设置终端标题
    echo -e "\e]0;$service_name\a"
    
    # 切换到服务目录并启动
    cd "$service_dir" && $service_cmd
}

# 配置设置
config_set() {
    if [[ ! -f "$CONFIG" ]]; then
        die "配置文件不存在，请先运行 ClewdR 生成配置"
    fi
    
    case "$1" in
        public) 
            log INFO "开放公网访问..."
            sed -i 's/127\.0\.0\.1/0.0.0.0/' "$CONFIG"
            log SUCCESS "已开放公网访问 (绑定到 0.0.0.0)"
            ;;
        port)
            read -p "请输入端口号 [1-65535]: " port
            
            if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
                die "无效的端口号: $port"
            fi
            
            sed -i -E "s/^(#?\s*port\s*=).*/port = $port/" "$CONFIG"
            log SUCCESS "端口已设置为: $port"
            ;;
        *)
            die "未知的配置选项: $1"
            ;;
    esac
}

# 创建 systemd 服务
create_systemd_service() {
    if [[ "$EUID" -ne 0 ]]; then
        die "创建系统服务需要 root 权限"
    fi
    
    if [[ ! -x "$CLEWDR_DIR/clewdr" ]]; then
        die "ClewdR 未安装，请先安装"
    fi
    
    log INFO "创建 systemd 服务文件..."
    
    cat > /etc/systemd/system/clewdr.service <<EOF
[Unit]
Description=ClewdR Service
After=network.target

[Service]
User=${SUDO_USER:-$(whoami)}
WorkingDirectory=$CLEWDR_DIR
ExecStart=$CLEWDR_DIR/clewdr
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log SUCCESS "ClewdR 系统服务已创建"
    
    echo
    echo "服务管理命令:"
    echo "  启动服务: systemctl start clewdr"
    echo "  停止服务: systemctl stop clewdr"  
    echo "  开机启动: systemctl enable clewdr"
    echo "  查看状态: systemctl status clewdr"
}

# 获取版本信息
get_versions() {
    local clewdr_status="未安装"
    local st_status="未安装"
    
    if [[ -x "$CLEWDR_DIR/clewdr" ]]; then
        clewdr_status="已安装"
    fi
    
    if [[ -d "$ST_DIR" ]]; then
        st_status="已安装"
    fi
    
    echo "$clewdr_status|$st_status"
}

# 显示主菜单
show_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${WHITE}     ClewdR & SillyTavern 管理工具     ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BLUE}安装管理:${NC}"
        echo -e "${GREEN}1)${NC} 安装/更新 ClewdR"
        echo -e "${GREEN}2)${NC} 安装/更新 SillyTavern"
        echo -e "${BLUE}服务启动:${NC}"
        echo -e "${GREEN}3)${NC} 启动 ClewdR"
        echo -e "${GREEN}4)${NC} 启动 SillyTavern"
        echo -e "${BLUE}ClewdR配置管理:${NC}"
        echo -e "${GREEN}5)${NC} 开放公网访问"
        echo -e "${GREEN}6)${NC} 设置端口号"
        echo -e "${GREEN}7)${NC} 创建系统服务"
        echo -e "${RED}0)${NC} 退出程序"
        echo -e "${CYAN}========================================${NC}"
        curl -s https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/log.log
        echo
        read -p "请选择操作 [0-7]: " opt
        
        case "$opt" in
            1) 
                check_deps
                install_clewdr 
                ;;
            2) 
                check_deps
                install_st 
                ;;
            3) 
                start_service "ClewdR" "$CLEWDR_DIR" "./clewdr" 
                ;;
            4) 
                start_service "SillyTavern" "$ST_DIR" "node server.js" 
                ;;
            5) 
                config_set public 
                ;;
            6) 
                config_set port 
                ;;
            7) 
                create_systemd_service 
                ;;
            0) 
                echo
                log SUCCESS "感谢使用！再见！"
                exit 0 
                ;;
            *) 
                log ERROR "无效选项: $opt，请重新选择"
                ;;
        esac
        
        echo
        read -n1 -p "按任意键继续..."
    done
}

main() {
    show_menu
}

# 脚本入口点
main "$@"