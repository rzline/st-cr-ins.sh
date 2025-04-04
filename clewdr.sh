#!/bin/bash

SOFTWARE_NAME="clewdr"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/${SOFTWARE_NAME}"
CONFIG_FILE="${TARGET_DIR}/config.toml"
GITHUB_REPO="Xerxes-2/clewdr"
GH_PROXY="https://ghfast.top/"
GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
VERSION_FILE="${TARGET_DIR}/version.txt"

if [ ! -d "$TARGET_DIR" ]; then
    echo "提示：目录 '$TARGET_DIR' 不存在。如果执行安装/更新，将会创建该目录。"
fi
if [ ! -f "$CONFIG_FILE" ]; then
    echo "警告：在 '$TARGET_DIR' 目录下找不到配置文件 '$CONFIG_FILE'。" >&2
    echo "      配置相关功能可能无法使用，或者在编辑时会创建新文件。" >&2
fi

handle_error() {
    echo "错误：${2}" >&2
    echo "操作中止。" >&2
    return ${1:-1}
}

detect_system() {
    echo "检测系统环境..."
    IS_TERMUX=false
    IS_MUSL=false

    if [[ -n "$PREFIX" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        IS_TERMUX=true
        echo "检测到Termux环境"
    else
        if command -v ldd >/dev/null 2>&1; then
             if ldd --version 2>&1 | grep -q -i 'musl' || \
                (command -v readelf &>/dev/null && readelf -l /bin/sh 2>/dev/null | grep -q 'program interpreter' && readelf -l /bin/sh 2>/dev/null | grep -q 'musl'); then
                IS_MUSL=true
                echo "检测到MUSL Linux环境"
             else
                echo "检测到标准Linux环境(glibc)"
             fi
        else
             echo "警告：无法找到 ldd 命令，无法准确判断 libc 类型。将假定为 glibc。"
             echo "      如果系统是 Alpine 等 musl 发行版，请在后续步骤手动选择 musl 版本。"
        fi
    fi

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armv8l) handle_error 1 "暂不支持32位ARM架构 ($ARCH)" && return 1 ;;
        *) handle_error 1 "不支持的系统架构: $ARCH" && return 1 ;;
    esac
    echo "检测到架构: $ARCH"

    if [ "$IS_TERMUX" = true ] && [ "$ARCH" != "aarch64" ]; then
        handle_error 1 "Termux环境当前仅支持aarch64架构" && return 1
    fi
    return 0
}

check_version() {
    echo "检查软件版本..."
    local LOCAL_VERSION=""
    LATEST_VERSION=""

    if [ ! -d "$TARGET_DIR" ]; then
        echo "未检测到安装目录 '$TARGET_DIR'，将执行首次安装。"
        return 0
    fi

    if [ -f "$VERSION_FILE" ]; then
        LOCAL_VERSION=$(cat "$VERSION_FILE")
        echo "当前已安装版本 (来自 $VERSION_FILE): $LOCAL_VERSION"
    else
        echo "未找到版本信息文件 '$VERSION_FILE'。"
        if [ -x "$TARGET_DIR/$SOFTWARE_NAME" ]; then
             echo "找到可执行文件，但版本未知。建议执行安装/更新以同步版本信息。"
        else
             echo "未找到可执行文件。"
        fi
        echo "将执行安装/更新。"
    fi

    echo "正在从 GitHub API 检查最新版本..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local api_url="$GH_API_URL"
    local use_proxy=false

    if [ -n "$country_code" ] && [ "$country_code" = "CN" ]; then
        echo "检测到中国大陆IP，将使用代理 '${GH_PROXY}' 获取版本信息。"
        api_url="${GH_PROXY}${GH_API_URL}"
        use_proxy=true
    fi

    local latest_info=$(curl -s --connect-timeout 10 "$api_url")
    if [ -z "$latest_info" ]; then
        echo "警告：无法从 '$api_url' 获取最新版本信息。可能是网络问题或 API 限制。" >&2
        if [ -n "$LOCAL_VERSION" ]; then
             read -p "是否仍要尝试强制更新？(y/N): " force_update
             if [[ "$force_update" =~ ^[Yy]$ ]]; then
                 echo "将尝试强制更新..."
                 LATEST_VERSION="unknown"
                 return 0
             else
                 echo "操作取消。"
                 return 1
             fi
        else
             echo "无法获取最新版本，但由于本地版本未知或未安装，将继续尝试安装。"
             LATEST_VERSION="unknown"
             return 0
        fi
    fi

    if command -v jq &> /dev/null; then
        LATEST_VERSION=$(echo "$latest_info" | jq -r .tag_name 2>/dev/null)
        if [[ "$LATEST_VERSION" == "null" ]]; then LATEST_VERSION=""; fi
    fi
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
    fi
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    fi


    if [ -z "$LATEST_VERSION" ]; then
        echo "警告：无法从 API 响应中解析出最新版本号。" >&2
        echo "API 响应内容如下 (前5行):"
        echo "$latest_info" | head -n 5
        if [ -n "$LOCAL_VERSION" ]; then
            read -p "是否仍要尝试强制更新？(y/N): " force_update_parse_fail
            if [[ "$force_update_parse_fail" =~ ^[Yy]$ ]]; then
                 echo "将尝试强制更新..."
                 LATEST_VERSION="unknown"
                 return 0
            else
                 echo "操作取消。"
                 return 1
            fi
        else
             echo "无法解析最新版本，但由于本地版本未知或未安装，将继续尝试安装。"
             LATEST_VERSION="unknown"
             return 0
        fi
    fi

    echo "最新版本: $LATEST_VERSION"

    if [ -z "$LOCAL_VERSION" ]; then
         echo "本地版本未知，执行安装。"
         return 0
    fi

    if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
        echo "当前已是最新版本 ($LOCAL_VERSION)。"
        read -p "是否强制重新安装？(y/N): " force_reinstall
        if [[ "$force_reinstall" =~ ^[Yy]$ ]]; then
            echo "将强制重新安装..."
            return 0
        else
            echo "无需更新。"
            return 1
        fi
    else
        echo "发现新版本，将从 '$LOCAL_VERSION' 更新到 '$LATEST_VERSION'"
        return 0
    fi
}

setup_download_url() {
    echo "配置下载选项..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    DOWNLOAD_URL_PREFIX=""
    FINAL_DOWNLOAD_FILENAME=""

    local gh_download_base_url=""
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "检测到国家代码: $country_code"
        if [ "$country_code" = "CN" ]; then
            echo "检测到中国大陆IP，默认启用GitHub代理: $GH_PROXY"
            read -p "是否禁用GitHub代理进行下载？(y/N): " disable_proxy
            if [[ "$disable_proxy" =~ ^[Yy]$ ]]; then
                gh_download_base_url="$GH_DOWNLOAD_URL_BASE"
                echo "已禁用GitHub代理，将直连GitHub下载。"
            else
                gh_download_base_url="${GH_PROXY}${GH_DOWNLOAD_URL_BASE}"
                echo "将使用GitHub代理下载: $GH_PROXY"
            fi
        else
            gh_download_base_url="$GH_DOWNLOAD_URL_BASE"
            echo "非中国大陆IP，将直连GitHub下载。"
        fi
    else
        echo "无法检测IP地理位置或国家代码无效，将直连GitHub下载。"
        gh_download_base_url="$GH_DOWNLOAD_URL_BASE"
    fi
    DOWNLOAD_URL_PREFIX="$gh_download_base_url"

    local download_filename=""
    if [ "$IS_TERMUX" = true ]; then
        download_filename="$SOFTWARE_NAME-android-$ARCH.zip"
        echo "Termux 环境，选择文件名: $download_filename"
    elif [ "$IS_MUSL" = true ]; then
        download_filename="$SOFTWARE_NAME-musllinux-$ARCH.zip"
        echo "MUSL 环境，选择文件名: $download_filename"
    else
        echo "检测到 glibc 环境。请选择二进制文件类型："
        echo "提示：如果 'ldd --version' 显示的版本低于 2.38，或不确定，建议选择 musl 版本。"
        echo "  1) glibc 版本 (标准 Linux, 通常兼容性更好，但可能需要较新 glibc)"
        echo "  2) musl 版本 (静态链接或依赖 musl libc, 通常更独立)"
        read -p "请输入选择 [1-2] (默认 1): " libc_choice

        case "${libc_choice:-1}" in
            2)
                download_filename="$SOFTWARE_NAME-musllinux-$ARCH.zip"
                echo "已选择 musl 版本文件名: $download_filename"
                ;;
            *)
                download_filename="$SOFTWARE_NAME-linux-$ARCH.zip"
                echo "已选择 glibc 版本文件名: $download_filename"
                ;;
        esac
    fi

    if [ -z "$download_filename" ]; then
         handle_error 1 "未能确定正确的下载文件名" && return 1
    fi
    FINAL_DOWNLOAD_FILENAME="$download_filename"
    return 0
}

download_and_install() {
    if [ -z "$DOWNLOAD_URL_PREFIX" ] || [ -z "$FINAL_DOWNLOAD_FILENAME" ]; then
        handle_error 1 "内部错误：下载 URL 前缀或文件名未设置" && return 1
    fi
    if [ -z "$LATEST_VERSION" ]; then
        echo "警告：无法获取最新版本号，将尝试下载 latest release。"
    elif [ "$LATEST_VERSION" == "unknown" ]; then
         echo "警告：最新版本号未知，将尝试下载 latest release。"
    fi


    echo "准备目标目录 '$TARGET_DIR'..."
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR" || { handle_error 1 "创建目录 '$TARGET_DIR' 失败" && return 1; }
        echo "已创建目标目录: $TARGET_DIR"
    else
        echo "目标目录已存在，将覆盖同名文件。"
    fi

    local download_url="$DOWNLOAD_URL_PREFIX/$FINAL_DOWNLOAD_FILENAME"
    local download_path="$TARGET_DIR/$FINAL_DOWNLOAD_FILENAME" # 下载到目标目录下
    echo "开始下载文件: $download_url"
    echo "保存到: $download_path"

    local max_retries=3
    local retry_count=0
    local wait_time=5
    while [ $retry_count -lt $max_retries ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$download_url" -o "$download_path" -#; then
            echo ""
            if [ -f "$download_path" ] && [ -s "$download_path" ]; then
                echo "下载成功。"
                break
            else
                echo "下载完成，但文件 '$download_path' 不存在或为空。"
            fi
        else
             echo ""
             echo "下载失败 (curl 退出码: $?)"
        fi

        rm -f "$download_path"
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "将在 $wait_time 秒后重试 ($retry_count/$max_retries)..."
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            handle_error 1 "下载失败：多次重试后仍无法成功下载 '$download_url'" && return 1
        fi
    done

    echo "开始解压文件 '$download_path' 到 '$TARGET_DIR'..."
    if unzip -oq "$download_path" -d "$TARGET_DIR"; then
        echo "解压成功。"
        rm -f "$download_path"
        echo "已删除下载的压缩文件 '$download_path'。"
    else
        rm -f "$download_path"
        handle_error 1 "解压失败: '$download_path'" && return 1
    fi

    local main_executable="$TARGET_DIR/$SOFTWARE_NAME"
    if [ -f "$main_executable" ]; then
        echo "设置执行权限: $main_executable"
        chmod +x "$main_executable" || echo "警告：设置执行权限失败，可能需要手动执行 chmod +x $main_executable"
    else
        echo "警告：解压后未在 '$TARGET_DIR' 找到预期的主程序文件 '$SOFTWARE_NAME'。"
    fi

    if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "unknown" ]; then
        echo "正在保存版本信息 '$LATEST_VERSION' 到 '$VERSION_FILE'..."
        mkdir -p "$(dirname "$VERSION_FILE")"
        echo "$LATEST_VERSION" > "$VERSION_FILE" || echo "警告：无法写入版本文件 '$VERSION_FILE'。"
    else
        echo "警告：无法获取或确认最新版本号，未更新版本文件 '$VERSION_FILE'。"
    fi

    echo "安装/更新过程完成！"
    echo "===================="
    echo "$SOFTWARE_NAME 已安装/更新到: $TARGET_DIR"
    if [ -f "$main_executable" ]; then
         echo "可执行文件是: $main_executable"
    fi
    echo "===================="
    return 0
}

function clewdrSettings {
    local current_version="未知"
    local main_executable="$TARGET_DIR/$SOFTWARE_NAME"
    local executable_found=false

    if [ -f "$VERSION_FILE" ]; then
        current_version=$(cat "$VERSION_FILE")
        if [ -x "$main_executable" ]; then
            executable_found=true
        else
            current_version="$current_version (但未找到或不可执行)"
        fi
    elif [ -d "$TARGET_DIR" ] && [ -x "$main_executable" ]; then
        executable_found=true
        exec_version=$("$main_executable" -v 2>&1)
        if [ $? -eq 0 ]; then
             current_version="$exec_version (无版本文件)"
        else
             current_version="未知 (执行 '$SOFTWARE_NAME -v' 失败, 无版本文件)"
        fi
    elif [ ! -d "$TARGET_DIR" ]; then
        current_version="未安装"
    else
        current_version="未知 (目录存在但无版本及执行文件)"
    fi
    clear
    echo "========================================="
    echo "          ${SOFTWARE_NAME} 管理菜单"
    echo "========================================="
    echo " 本地版本: $current_version"
    echo "-----------------------------------------"
    echo " 主要操作:"
    echo "   1) 启动 ${SOFTWARE_NAME}"
    echo "   2) 安装/更新 ${SOFTWARE_NAME}"
    echo "-----------------------------------------"
    echo " 配置操作:"
    echo "   3) 查看配置文件"
    echo "   4) 使用 Vim 编辑配置文件"
    echo "   5) 添加 Cookie 到配置文件"
    echo "   6) 修改 ${SOFTWARE_NAME} 监听端口"
    echo "-----------------------------------------"
    echo "   0) 退出脚本"
    echo "========================================="
    echo -n "请输入选项 [1-6, 0]: "

    read -n 1 option
    echo

    case $option in
        1)
            echo "--- 启动 ${SOFTWARE_NAME} ---"
            if $executable_found; then
                echo "正在尝试在目录 '$TARGET_DIR' 中启动 '$SOFTWARE_NAME'..."
                echo "按 Ctrl+C 停止程序。"
                cd "$TARGET_DIR" && ./"$SOFTWARE_NAME"
                local exit_code=$?
                echo ""
                echo "$SOFTWARE_NAME 已退出 (退出码: $exit_code)。"
                cd "$SCRIPT_DIR" || exit 1
            else
                echo "错误：未找到可执行文件 '$main_executable' 或文件不可执行。" >&2
                echo "请先执行安装/更新 (选项 0)。" >&2
            fi
            ;;
        2)
            echo "--- 安装/更新 ${SOFTWARE_NAME} (预编译版本) ---"
            local missing_deps=false
            for cmd in curl unzip; do
                 if ! command -v $cmd &> /dev/null; then
                     echo "错误：缺少依赖命令 '$cmd'。请先安装它。" >&2
                     missing_deps=true
                 fi
            done
            if $missing_deps; then return 1; fi

            detect_system || { echo "系统检测失败，中止安装/更新。" >&2; return 1; }
            check_version || { echo "版本检查表明无需更新或操作已取消。" >&2; return 1; }
            setup_download_url || { echo "下载配置失败，中止安装/更新。" >&2; return 1; }
            download_and_install || { echo "下载或安装失败，中止安装/更新。" >&2; return 1; }

            echo "安装/更新流程结束。您现在可以使用选项 '1' 启动程序。"
            ;;
        3)
            echo "--- 查看配置文件 (${CONFIG_FILE}) ---"
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo "错误：配置文件 '$CONFIG_FILE' 不存在。" >&2
            fi
            ;;
        4)
            echo "--- 编辑配置文件 (${CONFIG_FILE}) ---"
            if command -v vim &> /dev/null; then
                vim "$CONFIG_FILE"
                echo "编辑完成。"
            else
                echo "错误：未找到 vim 编辑器。请先安装 vim。" >&2
            fi
            ;;
        5)
            echo "--- 添加 Cookie 到配置文件 (${CONFIG_FILE}) ---"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "错误：配置文件 '$CONFIG_FILE' 不存在，无法添加 Cookie。" >&2
                echo "      请先创建或恢复配置文件 (例如使用选项2 或 运行安装/更新)。" >&2
            else
                echo "请输入包含 Cookie (sessionKey=...AA 格式) 的文本。"
                echo "每行可以包含一个或多个 Cookie，脚本会自动提取第一个找到的。"
                echo "输入完成后按 Ctrl+D 结束输入。"
                echo "-----------------------------------------"
                local cookies_added=0
                while IFS= read -r line; do
                    local extracted_cookie=$(echo "$line" | grep -E -o 'sessionKey=[a-zA-Z0-9+/_-]{100,130}AA' | head -n 1)

                    if [ -n "$extracted_cookie" ]; then
                        echo "在本行找到的 Cookie 是: $extracted_cookie"
                        if [[ $(tail -c1 "$CONFIG_FILE" | wc -l) -eq 0 ]]; then
                            echo "" >> "$CONFIG_FILE"
                        fi
                        printf "[[cookie_array]]\ncookie = \"%s\"\n" "$extracted_cookie" >> "$CONFIG_FILE"

                        if [ $? -eq 0 ]; then
                            echo "Cookie 已成功追加到 '$CONFIG_FILE' 文件末尾。"
                            cookies_added=$((cookies_added + 1))
                        else
                            echo "错误：尝试将 Cookie 追加到 '$CONFIG_FILE' 时出错。" >&2
                        fi
                    else
                        if [[ -n "$line" ]]; then
                            echo "提示：本行没有找到格式正确的 Cookie (需要包含 'sessionKey=...AA' 结构)。"
                        fi
                    fi
                done < /dev/stdin

                echo "-----------------------------------------"
                if [ $cookies_added -gt 0 ]; then
                    echo "共计 $cookies_added 个 Cookie 已添加。"
                else
                    echo "未添加任何新的 Cookie。"
                fi
            fi
            ;;
        6)
            echo "--- 修改监听端口 (Port) 在配置文件 (${CONFIG_FILE}) ---"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "错误：配置文件 '$CONFIG_FILE' 不存在。" >&2
            else
                local current_port=$(grep -E '^\s*port\s*=\s*([0-9]+)' "$CONFIG_FILE" | sed -E 's/.*=\s*([0-9]+)/\1/' | head -n 1)
                if [ -z "$current_port" ]; then current_port="未设置"; fi
                echo "当前配置文件中的 Port 为: $current_port"

                read -p "是否要修改配置文件中的监听端口 (Port)? (y/n) " choice
                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    read -p "请输入新的端口号 (1-65535, 例如 8000): " custom_port
                    if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -gt 0 ] && [ "$custom_port" -lt 65536 ]; then
                        if grep -q -E '^\s*port\s*=' "$CONFIG_FILE"; then
                            sed -i.bak 's/^\(\s*port\s*=\s*\)[0-9]*/\1'"$custom_port"'/' "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
                            echo "配置文件中的端口已修改为 $custom_port"
                        else
                            echo "" >> "$CONFIG_FILE"
                            echo "# 由管理脚本添加" >> "$CONFIG_FILE"
                            echo "port = $custom_port" >> "$CONFIG_FILE"
                            echo "注意：配置文件中未找到 'port' 配置项，已将其追加到文件末尾。"
                        fi
                        echo "端口修改成功。如果程序正在运行，需要重启才能生效。"
                    else
                        echo "错误：输入的端口号 '$custom_port' 无效。请输入 1 到 65535 之间的数字。" >&2
                    fi
                else
                    echo "操作取消，未修改配置文件中的端口号。"
                fi
            fi
            ;;
        0)
            echo "正在退出 ${SOFTWARE_NAME} 管理脚本..."
            return 1
            ;;
        *)
            echo "无效选项 '$option'。请输入菜单中显示的选项 [s, 0, 1-4, q]。" >&2
            ;;
    esac

    if [[ "$option" != "q" && "$option" != "Q" ]]; then
        echo -e "\n按任意键返回主菜单..."
        read -n 1 -s
    fi

    return 0

}

while true; do
    clewdrSettings
    ret_code=$?
    if [ $ret_code -ne 0 ]; then
        break
    fi
done

echo "脚本执行完毕。"
exit 0