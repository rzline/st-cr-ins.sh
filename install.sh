#!/bin/bash

SOFTWARE_NAME="clewdr"
GITHUB_REPO="Xerxes-2/clewdr"
DEFAULT_PROXY="https://ghfast.top/"

DOWNLOAD_FILE_PATTERN_LINUX="clewdr-linux-${ARCH}.zip"
DOWNLOAD_FILE_PATTERN_MUSL="clewdr-musllinux-${ARCH}.zip"
DOWNLOAD_FILE_PATTERN_TERMUX="clewdr-android-aarch64.zip"

handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo "错误：${error_msg}"
    exit ${exit_code}
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_SUBDIR="${SOFTWARE_NAME}"
TARGET_PATH="${SCRIPT_DIR}/${TARGET_SUBDIR}"

GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_DOWNLOAD_URL="${GH_DOWNLOAD_URL_BASE}"

IS_TERMUX=false
IS_MUSL=false
DETECTED_COUNTRY=""
PLATFORM_ARCH=""
ARCH=""


# 下载函数
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    local wait_time=5

    echo "准备下载: ${url}"
    echo "保存到: ${output}"
    while [ $retry_count -lt $max_retries ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 --show-error "$url" -o "$output" -#; then
            echo ""
            if [ -f "$output" ] && [ -s "$output" ]; then
                echo "下载成功: ${output}"
                return 0
            else
                echo "下载完成但文件无效或为空: ${output}"
                rm -f "$output"
            fi
        else
             echo ""
             echo "下载命令执行失败 (curl exit code: $?)"
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "下载失败，${wait_time} 秒后进行第 $((retry_count + 1)) 次重试..."
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            echo "下载失败，已重试 $max_retries 次"
            return 1
        fi
    done
    return 1
}

# 环境检查
check_prerequisites() {
    echo "检查运行环境..."
    if ! command -v curl >/dev/null 2>&1; then
        handle_error 1 "未找到 curl 命令，请先安装 (例如: apt update && apt install curl 或 pkg install curl)"
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        handle_error 1 "未找到 unzip 命令，请先安装 (例如: apt update && apt install unzip 或 pkg install unzip)"
    fi
    if ! command -v ldd >/dev/null 2>&1; then
        echo "警告: 未找到 ldd 命令，可能无法准确检测 MUSL 环境。将尝试下载标准 glibc 版本。"
    fi
    echo "环境检查通过。"
}

# 检测 IP 地理位置
detect_country() {
    echo "检测 IP 地理位置..."
    country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$country_code" ]; then
        if [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
            DETECTED_COUNTRY="$country_code"
            echo "检测到国家代码: ${DETECTED_COUNTRY}"
        else
            echo "警告: 获取到无效的国家代码格式 (${country_code})，无法确定地理位置。"
            DETECTED_COUNTRY="UNKNOWN"
        fi
    else
        echo "警告: 无法自动检测地理位置 (curl 退出码: ${exit_code})。"
        DETECTED_COUNTRY="UNKNOWN"
    fi
}

# 配置 GitHub 代理
configure_proxy() {
    local use_proxy=false

    if [ "${DETECTED_COUNTRY}" == "CN" ]; then
        echo "检测到中国大陆 IP，默认启用 GitHub 代理: ${DEFAULT_PROXY}"
        use_proxy=true

        # 询问用户是否禁用默认代理
        local disable_proxy_choice=""
        read -p "是否禁用此代理并尝试直连 GitHub? (y/N): " disable_proxy_choice
        case "${disable_proxy_choice}" in
            [yY])
                echo "已禁用默认代理，将尝试直连 GitHub。"
                use_proxy=false
                ;;
            *)
                echo "将使用默认代理。"
                use_proxy=true
                ;;
        esac
    else
        echo "未检测到中国大陆 IP (${DETECTED_COUNTRY})，默认不使用 GitHub 代理。"
        use_proxy=false
    fi

    if [ "$use_proxy" = true ]; then
        if [[ "${DEFAULT_PROXY}" != */ ]]; then
            DEFAULT_PROXY="${DEFAULT_PROXY}/"
        fi
        GH_DOWNLOAD_URL="${DEFAULT_PROXY}${GH_DOWNLOAD_URL_BASE}"
        echo "GitHub 下载将通过代理: ${DEFAULT_PROXY}"
    else
        GH_DOWNLOAD_URL="${GH_DOWNLOAD_URL_BASE}"
        echo "GitHub 下载将尝试直连。"
    fi
    echo "---"
}


# 检测运行环境
detect_environment() {
    echo "检测运行环境..."
    if [[ -n "$PREFIX" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        IS_TERMUX=true
        echo "检测到 Termux 环境。"
    else
        IS_TERMUX=false
        if command -v ldd >/dev/null 2>&1; then
            if ldd --version 2>&1 | grep -q -i 'musl'; then
                IS_MUSL=true
                echo "检测到 MUSL Linux 环境。"
            else
                IS_MUSL=false
                echo "检测到标准 (glibc) Linux 环境。"
            fi
        else
            IS_MUSL=false
            echo "无法确认是否为 MUSL 环境（缺少 ldd），将按标准 (glibc) Linux 处理。"
        fi
    fi
}

# 获取平台架构
detect_architecture() {
    echo "检测系统架构..."
    PLATFORM_ARCH=$(uname -m)
    ARCH="UNKNOWN"

    if [ "$PLATFORM_ARCH" = "x86_64" ]; then
      ARCH=amd64
    elif [ "$PLATFORM_ARCH" = "aarch64" ]; then
      ARCH=arm64
    elif [ "$PLATFORM_ARCH" = "armv7l" ] || [ "$PLATFORM_ARCH" = "armv8l" ]; then
        handle_error 1 "clewdr 不支持 32 位 ARM 架构 (${PLATFORM_ARCH})。"
    fi

    if [ "$IS_TERMUX" = true ] && [ "$PLATFORM_ARCH" != "aarch64" ]; then
        handle_error 1 "检测到 Termux 环境，但架构 (${PLATFORM_ARCH}) 不是 aarch64。clewdr 的 Termux 版本仅支持 aarch64。"
    fi

    if [ "$ARCH" == "UNKNOWN" ]; then
      handle_error 1 "不支持的平台架构: ${PLATFORM_ARCH}。"
    fi
    echo "检测到架构: ${ARCH} (原始平台: ${PLATFORM_ARCH})"
}

# 准备目标目录
prepare_target_dir() {
    echo "准备目标目录: ${TARGET_PATH}"
    if [ -d "$TARGET_PATH" ]; then
        echo "警告：目录 ${TARGET_PATH} 已存在。"
        echo "正在清空目录 ${TARGET_PATH} ..."
        find "${TARGET_PATH}" -mindepth 1 -delete || handle_error 1 "无法清空目录 ${TARGET_PATH}"
    else
        mkdir -p "$TARGET_PATH" || handle_error 1 "无法创建目录 ${TARGET_PATH}"
    fi
    echo "目标目录准备就绪。"
}

# 执行安装
do_install() {
    echo "开始下载和解压 ${SOFTWARE_NAME}..."

    local selected_pattern=""
    local download_filename=""
    local env_type=""

    if [ "$IS_TERMUX" = true ]; then
        selected_pattern="${DOWNLOAD_FILE_PATTERN_TERMUX}"
        download_filename="${selected_pattern}"
        env_type="Termux (aarch64)"
    elif [ "$IS_MUSL" = true ]; then
        selected_pattern="${DOWNLOAD_FILE_PATTERN_MUSL}"
        download_filename=$(eval echo "${selected_pattern}")
        env_type="MUSL Linux"
    else
        selected_pattern="${DOWNLOAD_FILE_PATTERN_LINUX}"
        download_filename=$(eval echo "${selected_pattern}")
        env_type="Standard Linux (glibc)"
    fi

    echo "使用 ${env_type} 下载模式。"

    if [ -z "$download_filename" ] || [[ "$selected_pattern" == *"PLEASE_CONFIGURE"* ]]; then
         handle_error 1 "无法确定下载文件名或下载模式未配置 (环境: ${env_type}, 架构: ${ARCH}, 原始架构: ${PLATFORM_ARCH})。"
    fi

    local full_download_url="${GH_DOWNLOAD_URL}/${download_filename}"
    local download_save_path="${TARGET_PATH}/${download_filename}"

    if ! download_file "${full_download_url}" "${download_save_path}"; then
        handle_error 1 "下载 ${SOFTWARE_NAME} 失败！URL: ${full_download_url}"
    fi

    echo "正在解压文件 ${download_save_path} 到 ${TARGET_PATH} ..."
    if ! unzip -o "${download_save_path}" -d "${TARGET_PATH}/"; then
        rm -f "${download_save_path}"
        handle_error 1 "解压 ${download_save_path} 失败！"
    fi

    echo "清理下载的压缩文件..."
    rm -f "${download_save_path}"

    echo "${SOFTWARE_NAME} 文件已下载并解压到 ${TARGET_PATH}"

    if [ -f "${TARGET_PATH}/clewdr" ]; then
       echo "设置 clewdr 为可执行..."
       chmod +x "${TARGET_PATH}/clewdr"
    else
       echo "警告：未在 ${TARGET_PATH} 找到名为 'clewdr' 的文件来设置执行权限。"
    fi
}


main() {
    check_prerequisites
    detect_country
    configure_proxy
    detect_environment
    detect_architecture
    prepare_target_dir
    do_install
    echo "---------------------------------------------"
    echo "操作完成。"
    echo "clewdr 已安装到: ${TARGET_PATH}"
    echo "你可以尝试运行: ${TARGET_PATH}/clewdr"
    echo "---------------------------------------------"
}

main

exit 0
