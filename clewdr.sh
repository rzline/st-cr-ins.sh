#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/clewdr"
CONFIG_FILE="${TARGET_DIR}/config.toml"
GITHUB_REPO="Xerxes-2/clewdr"
GH_PROXY="https://ghfast.top/"
GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
VERSION_FILE="${TARGET_DIR}/version.txt"

SILLY_TAVERN_DIR="${SCRIPT_DIR}/SillyTavern"
SILLY_TAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git"

if [ ! -d "$TARGET_DIR" ]; then
    echo "提示：目录 '$TARGET_DIR' 不存在。如果执行安装/更新clewdr，将会创建该目录。"
fi
if [ ! -f "$CONFIG_FILE" ]; then
    echo "警告：在 '$TARGET_DIR' 目录下找不到配置文件 '$CONFIG_FILE'。" >&2
    echo "clewdr配置相关功能可能无法使用，或者在编辑时会创建新文件。" >&2
fi

handle_error() {
    echo "错误：${2}" >&2
    echo "操作中止。" >&2
    return "${1:-1}"
}

detect_system() {
    echo "检测系统环境 (用于clewdr安装)..."
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
    echo "检查clewdr软件版本..."
    local LOCAL_VERSION=""
    LATEST_VERSION=""

    if [ ! -d "$TARGET_DIR" ]; then
        echo "未检测到clewdr安装目录 '$TARGET_DIR'，将执行首次安装。"
        return 0
    fi

    if [ -f "$VERSION_FILE" ]; then
        LOCAL_VERSION=$(cat "$VERSION_FILE")
        echo "当前已安装版本 (来自 $VERSION_FILE): $LOCAL_VERSION"
    else
        echo "未找到clewdr版本信息文件 '$VERSION_FILE'。"
        if [ -x "$TARGET_DIR/$SOFTWARE_NAME" ]; then
             echo "找到clewdr可执行文件，但版本未知。建议执行安装/更新以同步版本信息。"
        else
             echo "未找到clewdr可执行文件。"
        fi
        echo "将执行安装/更新。"
    fi

    echo "正在从 GitHub API 检查clewdr最新版本..."
    local country_code
    country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local curl_exit_status=$?
    local api_url="$GH_API_URL"

    local latest_info
    latest_info=$(curl -s --connect-timeout 10 "$api_url")
    local curl_exit_status=$?
    if [ -z "$latest_info" ]; then
        echo "警告：无法从 '$api_url' 获取最新版本信息。可能是网络问题或 API 限制。" >&2
        if [ -n "$LOCAL_VERSION" ]; then
             read -rp "是否仍要尝试强制更新clewdr？(y/N): " force_update
             if [[ "$force_update" =~ ^[Yy]$ ]]; then
                 echo "将尝试强制更新clewdr..."
                 LATEST_VERSION="unknown"
                 return 0
             else
                 echo "操作取消。"
                 return 1
             fi
        else
             echo "无法获取最新版本，但由于本地版本未知或未安装，将继续尝试安装clewdr。"
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
        echo "警告：无法从 API 响应中解析出clewdr最新版本号。" >&2
        echo "API 响应内容如下 (前5行):"
        echo "$latest_info" | head -n 5
        if [ -n "$LOCAL_VERSION" ]; then
            read -rp "是否仍要尝试强制更新clewdr？(y/N): " force_update_parse_fail
            if [[ "$force_update_parse_fail" =~ ^[Yy]$ ]]; then
                 echo "将尝试强制更新clewdr..."
                 LATEST_VERSION="unknown"
                 return 0
            else
                 echo "操作取消。"
                 return 1
            fi
        else
             echo "无法解析最新版本，但由于本地版本未知或未安装，将继续尝试安装clewdr。"
             LATEST_VERSION="unknown"
             return 0
        fi
    fi

    echo "clewdr最新版本: $LATEST_VERSION"

    if [ -z "$LOCAL_VERSION" ]; then
         echo "clewdr本地版本未知，执行安装。"
         return 0
    fi

    if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
        echo "当前clewdr已是最新版本 ($LOCAL_VERSION)。"
        read -rp "是否强制重新安装clewdr？(y/N): " force_reinstall
        if [[ "$force_reinstall" =~ ^[Yy]$ ]]; then
            echo "将强制重新安装clewdr..."
            return 0
        else
            echo "无需更新clewdr。"
            return 1
        fi
    else
        echo "发现新版本，将从 '$LOCAL_VERSION' 更新到 '$LATEST_VERSION'"
        return 0
    fi
}

setup_download_url() {
    echo "配置clewdr下载选项..."
    local country_code
    country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local curl_exit_status=$?
    DOWNLOAD_URL_PREFIX=""
    FINAL_DOWNLOAD_FILENAME=""

    local gh_download_base_url=""
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "检测到国家代码: $country_code"
        if [ "$country_code" = "CN" ]; then
            echo "检测到中国大陆IP，默认启用GitHub代理: $GH_PROXY"
            read -rp "是否禁用GitHub代理进行下载？(y/N): " disable_proxy
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
        echo "检测到 glibc 环境。请选择clewdr二进制文件类型："
        echo "提示：如果 'ldd --version' 显示的版本低于 2.38，或不确定，建议选择 musl 版本。"
        echo "  1) glibc 版本 (标准 Linux, 通常兼容性更好，但可能需要较新 glibc)"
        echo "  2) musl 版本 (静态链接或依赖 musl libc, 通常更独立)"
        read -rp "请输入选择 [1-2] (默认 1): " libc_choice

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
         handle_error 1 "未能确定正确的clewdr下载文件名" && return 1
    fi
    FINAL_DOWNLOAD_FILENAME="$download_filename"
    return 0
}

download_and_install() {
    if [ -z "$DOWNLOAD_URL_PREFIX" ] || [ -z "$FINAL_DOWNLOAD_FILENAME" ]; then
        handle_error 1 "内部错误：clewdr下载 URL 前缀或文件名未设置" && return 1
    fi
    if [ -z "$LATEST_VERSION" ]; then
        echo "警告：无法获取clewdr最新版本号，将尝试下载 latest release。"
    elif [ "$LATEST_VERSION" == "unknown" ]; then
         echo "警告：clewdr最新版本号未知，将尝试下载 latest release。"
    fi


    echo "准备clewdr目标目录 '$TARGET_DIR'..."
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR" || { handle_error 1 "创建目录 '$TARGET_DIR' 失败" && return 1; }
        echo "已创建clewdr目标目录: $TARGET_DIR"
    else
        echo "clewdr目标目录已存在，将覆盖同名文件。"
    fi

    local download_url="$DOWNLOAD_URL_PREFIX/$FINAL_DOWNLOAD_FILENAME"
    local download_path="$TARGET_DIR/$FINAL_DOWNLOAD_FILENAME"
    echo "开始下载clewdr文件: $download_url"
    echo "保存到: $download_path"

    local max_retries=3
    local retry_count=0
    local wait_time=5
    while [ $retry_count -lt $max_retries ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$download_url" -o "$download_path"; then
            echo ""
            if [ -f "$download_path" ] && [ -s "$download_path" ]; then
                echo "clewdr下载成功。"
                break
            else
                echo "下载完成，但文件 '$download_path' 不存在或为空。"
            fi
        else
            echo ""
            echo "clewdr下载失败 (curl 退出码: $?)"
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
        echo "正在保存clewdr版本信息 '$LATEST_VERSION' 到 '$VERSION_FILE'..."
        mkdir -p "$(dirname "$VERSION_FILE")"
        echo "$LATEST_VERSION" > "$VERSION_FILE" || echo "警告：无法写入版本文件 '$VERSION_FILE'。"
    else
        echo "警告：无法获取或确认clewdr最新版本号，未更新版本文件 '$VERSION_FILE'。"
    fi

    echo "clewdr安装/更新过程完成！"
    echo "===================="
    echo "$SOFTWARE_NAME 已安装/更新到: $TARGET_DIR"
    if [ -f "$main_executable" ]; then
         echo "可执行文件是: $main_executable"
    fi
    echo "===================="
    return 0
}

install_sillytavern() {
    echo "--- 安装/更新SillyTavern---"

    echo "检查依赖: git, npm, curl..."
    local missing_dep=false
    if ! command -v git &> /dev/null; then
        echo "错误：未找到 'git' 命令。请先安装 git。" >&2
        missing_dep=true
    fi
    if ! command -v npm &> /dev/null; then
        echo "错误：未找到 'npm' 命令。请先安装 Node.js 和 npm。" >&2
        missing_dep=true
    fi
     if ! command -v curl &> /dev/null; then
        echo "错误：未找到 'curl' 命令（用于检测地区以启用代理）。请先安装 curl。" >&2
        missing_dep=true
    fi
    if $missing_dep; then
        echo "操作中止。" >&2
        return 1
    fi
    echo "依赖检查通过。"

    local git_cmd="git"
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local use_git_proxy=false

    echo "检测地理位置以确定是否需要 Git 代理..."
    if [ -n "$country_code" ] && [ "$country_code" = "CN" ]; then
        echo "检测到中国大陆IP ($country_code)，默认将为 Git 操作启用代理: $GH_PROXY"
        read -rp "是否禁用 Git 代理进行 clone/pull？(y/N): " disable_git_proxy
        if [[ ! "$disable_git_proxy" =~ ^[Yy]$ ]]; then
            use_git_proxy=true
            git_cmd="git -c http.proxy=${GH_PROXY} -c https.proxy=${GH_PROXY}"
            echo "已启用 Git 代理。"
        else
            echo "已禁用 Git 代理，将直连 GitHub。"
        fi
    else
        if [ -n "$country_code" ]; then
             echo "检测到非中国大陆IP ($country_code)，将不使用 Git 代理。"
        else
             echo "无法检测地理位置，将不使用 Git 代理。"
        fi
    fi

    local needs_clone=false
    local proceed_npm_install=false

    if [ -d "$SILLY_TAVERN_DIR" ]; then
        echo "检测到SillyTavern目录: $SILLY_TAVERN_DIR"
        if [ -d "$SILLY_TAVERN_DIR/.git" ]; then
            echo "这是一个 Git 仓库。尝试使用 '${git_cmd} pull' 更新..."
            cd "$SILLY_TAVERN_DIR" || { echo "错误：无法进入目录 '$SILLY_TAVERN_DIR'" >&2 ; return 1; }

            local stash_needed=false
            if ! git diff --quiet || ! git diff --cached --quiet; then
                echo "检测到本地修改，将尝试使用 'git stash' 暂存..."
                if ${git_cmd} stash push -m "Stashed by clewdr.sh before pull"; then
                    echo "'git stash' 成功。"
                    stash_needed=true
                else
                    echo "警告：'git stash' 失败。如果 'git pull' 失败，可能需要手动解决冲突。" >&2
                fi
            fi

            if ${git_cmd} pull; then
                echo "'${git_cmd} pull' 成功完成。"
                proceed_npm_install=true
                if [ "$stash_needed" = true ]; then
                    echo "尝试恢复之前暂存的修改 ('git stash pop')..."
                    if ${git_cmd} stash pop; then
                        echo "'git stash pop' 成功。"
                    else
                        echo "警告：'git stash pop' 失败。可能存在冲突，请进入 '$SILLY_TAVERN_DIR' 手动执行 'git stash apply' 或 'git stash drop' 并解决。" >&2
                    fi
                fi
            else
                local pull_exit_code=$?
                echo "错误：'${git_cmd} pull' 失败 (退出码: $pull_exit_code)。" >&2
                echo "可能原因：网络问题、代理配置错误、或本地修改与远程仓库存在冲突。" >&2
                if [ "$use_git_proxy" = true ]; then
                     echo "      (已尝试使用代理: $GH_PROXY)"
                fi
                 if [ "$stash_needed" = true ]; then
                     echo "      (尝试过 'git stash'，但 pull 仍然失败。请检查 '$SILLY_TAVERN_DIR' 中的 'git status'。)"
                 else
                     echo "请手动进入 '$SILLY_TAVERN_DIR' 目录，使用 'git status' 查看状态并解决冲突，然后再次尝试 '${git_cmd} pull'。" >&2
                 fi
                cd "$SCRIPT_DIR" || exit 1
                echo "操作中止。"
                return 1
            fi
            cd "$SCRIPT_DIR" || exit 1
        else
            echo "警告：目录存在，但它不是一个 Git 仓库。" >&2
            echo "      直接克隆到此位置通常会失败，除非目录为空。" >&2
            read -rp "是否仍然尝试在此位置克隆？ [风险] 如果目录非空，克隆会失败。 (y/N): " confirm_clone_over_nonrepo
            if [[ "$confirm_clone_over_nonrepo" =~ ^[Yy]$ ]]; then
                echo "将尝试克隆。如果失败，请确保目录 '$SILLY_TAVERN_DIR' 是空的。"
                needs_clone=true
            else
                echo "操作取消。"
                return 1
            fi
        fi
    else
        echo "目录 '$SILLY_TAVERN_DIR' 不存在，将执行克隆。"
        needs_clone=true
    fi

    if [ "$needs_clone" = true ]; then
        echo "准备使用 '${git_cmd} clone' 克隆SillyTavern到 '$SILLY_TAVERN_DIR'..."
        cd "$SCRIPT_DIR" || { echo "错误：无法切换回脚本目录 '$SCRIPT_DIR'" >&2; return 1; }

        if ${git_cmd} clone --depth 1 --branch main "$SILLY_TAVERN_REPO" "$SILLY_TAVERN_DIR"; then
            echo "克隆成功。"
            proceed_npm_install=true
        else
             local clone_exit_code=$?
             echo "错误：'${git_cmd} clone' 失败 (退出码: $clone_exit_code)" >&2
             echo "可能原因：目标目录已存在且非空、网络问题、Git 代理配置错误、权限不足。" >&2
              if [ "$use_git_proxy" = true ]; then
                     echo "      (已尝试使用代理: $GH_PROXY)"
              fi
             if [ -d "$SILLY_TAVERN_DIR" ]; then
                echo "尝试清理部分克隆的目录 '$SILLY_TAVERN_DIR'..."
                rm -rf "$SILLY_TAVERN_DIR"
             fi
             return 1
        fi
    fi

    if [ "$proceed_npm_install" = true ]; then
        echo "切换到SillyTavern目录: $SILLY_TAVERN_DIR"
        cd "$SILLY_TAVERN_DIR" || { echo "错误：无法切换到目录 '$SILLY_TAVERN_DIR'" >&2; cd "$SCRIPT_DIR" || exit 1; return 1; }

        if [ ! -f "package.json" ]; then
            echo "错误：在 '$SILLY_TAVERN_DIR' 中未找到 'package.json' 文件。无法执行 npm install。" >&2
            cd "$SCRIPT_DIR" || exit 1
            return 1
        fi

        echo "执行: npm install (这可能需要一些时间)..."
        local npm_cmd="npm install"
        if [ "$use_git_proxy" = true ]; then
             echo "检测到之前使用了 Git 代理，将尝试为 npm 设置代理..."
             npm_cmd="npm install --proxy=$GH_PROXY --https-proxy=$GH_PROXY"
             echo "将使用命令: $npm_cmd"
        fi

        if $npm_cmd; then
            echo "npm install 成功完成。"
        else
            local npm_exit_code=$?
            echo "错误：'$npm_cmd' 失败 (退出码: $npm_exit_code)" >&2
            echo "请检查 Node.js/npm 是否正确安装、网络连接以及是否有足够的权限。" >&2
            if [ "$use_git_proxy" = false ]; then
                echo "提示：如果网络不佳或在中国大陆，可能需要为 npm 配置代理。" >&2
                echo "      可以尝试手动执行: cd \"$SILLY_TAVERN_DIR\" && npm install --proxy=$GH_PROXY --https-proxy=$GH_PROXY" >&2
            fi
            cd "$SCRIPT_DIR" || exit 1
            return 1
        fi
        cd "$SCRIPT_DIR" || exit 1
    else
        echo "由于之前的步骤未成功或被取消，未执行 npm install。"
        return 1
    fi

    echo "-----------------------------------------"
    echo "SillyTavern安装/更新成功完成！"
    echo "目录: $SILLY_TAVERN_DIR"
    echo "你可以使用本脚本菜单中的选项 '8' 来启动SillyTavern，"
    echo "或者手动执行以下命令:"
    echo "cd \"$SILLY_TAVERN_DIR\""
    echo "node server.js"
    echo "-----------------------------------------"
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
        local exec_version_output
        exec_version_output=$("$main_executable" -v 2>&1)
        if [ $? -eq 0 ] && [[ "$exec_version_output" == *"clewdr v"* ]]; then
             current_version=$(echo "$exec_version_output" | grep -o 'v[0-9.]*')
             current_version="$current_version (无版本文件)"
        else
             current_version="未知 (执行 '$SOFTWARE_NAME -v' 失败或格式不对, 无版本文件)"
        fi
    elif [ ! -d "$TARGET_DIR" ]; then
        current_version="未安装"
    else
        current_version="未知 (目录存在但无版本及执行文件)"
    fi

    local silly_tavern_status="未知"
    local st_server_script="$SILLY_TAVERN_DIR/server.js"
    if [ -d "$SILLY_TAVERN_DIR" ] && [ -f "$st_server_script" ] && [ -d "$SILLY_TAVERN_DIR/.git" ]; then
        silly_tavern_status="已安装 (Git 仓库)"
    elif [ -d "$SILLY_TAVERN_DIR" ] && [ -f "$st_server_script" ]; then
         silly_tavern_status="已安装 (非 Git 仓库?)"
    elif [ -d "$SILLY_TAVERN_DIR" ]; then
        silly_tavern_status="目录存在但可能未完成安装 (缺少 server.js?)"
    else
        silly_tavern_status="未安装"
    fi

    clear
    echo "========================================="
    echo "            酒馆小工具"
    echo "========================================="
    echo "clewdr本地版本: $current_version"
    echo "SillyTavern状态: $silly_tavern_status"
    echo "-----------------------------------------"
    echo "clewdr操作:"
    echo "   1) 启动clewdr"
    echo "   2) 安装/更新"
    echo "   3) 查看clewdr配置文件"
    echo "   4) 使用 Vim 编辑clewdr配置文件"
    echo "   5) 添加 Cookie 到clewdr配置文件"
    echo "   6) 修改clewdr监听端口"
    echo "-----------------------------------------"
    echo "SillyTavern操作:"
    echo "   7) 启动"
    echo "   8) 安装/更新"
    echo "-----------------------------------------"
    echo "   0) 退出脚本"
    echo "========================================="
    echo -n "请输入选项 [1-8, 0]: "

    read -n 1 option
    echo

    case $option in
        1)
            echo "--- 启动clewdr---"
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
                echo "请先执行安装/更新 (选项 2)。" >&2
            fi
            ;;
        2)
            echo "--- 安装/更新clewdr---"
            local missing_deps=false
            for cmd in curl unzip; do
                 if ! command -v $cmd &> /dev/null; then
                     echo "错误：缺少依赖命令 '$cmd'。请先安装它。" >&2
                     missing_deps=true
                 fi
            done
            if ! command -v jq &> /dev/null; then
                 echo "提示：未找到 'jq' 命令。版本检查将使用 grep/cut，可能不太稳定。"
            fi
            if $missing_deps; then return 1; fi

            detect_system || { echo "系统检测失败，中止安装/更新。" >&2; return 1; }
            check_version || { echo "版本检查表明无需更新或操作已取消。" >&2; return 1; }
            setup_download_url || { echo "下载配置失败，中止安装/更新。" >&2; return 1; }
            download_and_install || { echo "下载或安装失败，中止安装/更新。" >&2; return 1; }

            echo "安装/更新流程结束。您现在可以使用选项 '1' 启动程序。"
            ;;
        3)
            echo "--- 查看clewdr配置文件 (${CONFIG_FILE}) ---"
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo "错误：配置文件 '$CONFIG_FILE' 不存在。" >&2
            fi
            ;;
        4)
            echo "--- 编辑clewdr配置文件 (${CONFIG_FILE}) ---"
            if command -v vim &> /dev/null; then
                vim "$CONFIG_FILE"
                echo "编辑完成。"
            elif command -v nano &> /dev/null; then
                 echo "未找到 vim，尝试使用 nano..."
                 nano "$CONFIG_FILE"
                 echo "编辑完成。"
            else
                echo "错误：未找到 vim 或 nano 编辑器。请先安装一个。" >&2
            fi
            ;;
        5)
            echo "--- 添加 Cookie 到clewdr配置文件 (${CONFIG_FILE}) ---"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "错误：配置文件 '$CONFIG_FILE' 不存在，无法添加 Cookie。" >&2
                echo "      请先创建或恢复配置文件 (例如通过选项 2 安装/更新clewdr后首次运行它，或手动创建)。" >&2
            else
                echo "请输入包含 Cookie (sessionKey=...AA 格式) 的文本。"
                echo "每行可以包含一个或多个 Cookie，脚本会自动提取第一个找到的。"
                echo "输入完成后按 Ctrl+D 结束输入。"
                echo "-----------------------------------------"
                local cookies_added=0
                while IFS= read -r line; do
                local extracted_cookie
                extracted_cookie=$(echo "$line" | grep -E -o 'sessionKey=(sk-ant-sid[a-zA-Z0-9_-]+|[a-zA-Z0-9+/_-]{100,})' | head -n 1)
                local pipeline_status=$?
                    if [ -n "$extracted_cookie" ]; then
                        if [[ "$extracted_cookie" == "sessionKey=sk-ant-sid"* || ( ${#extracted_cookie} -ge 100 && ${#extracted_cookie} -le 140 ) ]]; then
                             echo "在本行找到的 Cookie 是: $extracted_cookie"
                             if [[ $(tail -c1 "$CONFIG_FILE" | wc -l) -eq 0 ]]; then
                                 echo "" >> "$CONFIG_FILE"
                             fi
                             printf "\n[[cookie_array]]\ncookie = \"%s\"\n" "$extracted_cookie" >> "$CONFIG_FILE"

                             if [ $? -eq 0 ]; then
                                 echo "Cookie 已成功追加到 '$CONFIG_FILE' 文件末尾。"
                                 cookies_added=$((cookies_added + 1))
                             else
                                 echo "错误：尝试将 Cookie 追加到 '$CONFIG_FILE' 时出错。" >&2
                             fi
                        else
                             echo "提示：找到 'sessionKey=' 但长度 (${#extracted_cookie}) 不符合预期 (100-140 字符，非 sk-ant-sid 格式)，已跳过。"
                        fi
                    else
                        if [[ -n "$line" ]]; then
                            echo "提示：本行没有找到 'sessionKey=...' 结构。"
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
            echo "--- 修改clewdr监听端口 (Port) 在配置文件 (${CONFIG_FILE}) ---"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "错误：配置文件 '$CONFIG_FILE' 不存在。" >&2
            else
                local current_port
                current_port=$(grep -E '^\s*port\s*=\s*([0-9]+)\s*(#.*)?$' "$CONFIG_FILE" | sed -E 's/^\s*port\s*=\s*([0-9]+).*/\1/' | head -n 1)
                local pipeline_status=$? # 可选
                if [ -z "$current_port" ]; then current_port="未设置 (将使用clewdr默认值)"; fi
                echo "当前配置文件中的 Port 为: $current_port"

                read -rp "是否要修改配置文件中的监听端口 (Port)? (y/n) " choice
                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    read -rp "请输入新的端口号 (1-65535, 例如 8000): " custom_port
                    if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -gt 0 ] && [ "$custom_port" -lt 65536 ]; then
                        if grep -q -E '^\s*#?\s*port\s*=' "$CONFIG_FILE"; then
                            sed -i.bak -E 's/^\s*#?\s*(port\s*=\s*)[0-9]+(.*)$/\1'"$custom_port"'\2/' "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
                            echo "配置文件中的端口已修改为 $custom_port (并确保已取消注释)"
                        else
                            if [[ $(tail -c1 "$CONFIG_FILE" | wc -l) -eq 0 ]]; then echo "" >> "$CONFIG_FILE"; fi
                            echo "" >> "$CONFIG_FILE"
                            echo "# 由管理脚本添加/修改" >> "$CONFIG_FILE"
                            echo "port = $custom_port" >> "$CONFIG_FILE"
                            echo "注意：配置文件中未找到 'port' 配置项，已将其追加到文件末尾。"
                        fi
                        echo "端口修改成功。如果 $SOFTWARE_NAME 正在运行，需要重启才能生效。"
                    else
                        echo "错误：输入的端口号 '$custom_port' 无效。请输入 1 到 65535 之间的数字。" >&2
                    fi
                else
                    echo "操作取消，未修改配置文件中的端口号。"
                fi
            fi
            ;;
        7)
            echo "--- 启动SillyTavern---"
            local st_server_script="$SILLY_TAVERN_DIR/server.js"
            if [ -d "$SILLY_TAVERN_DIR" ] && [ -f "$st_server_script" ]; then
                if command -v node &> /dev/null; then
                    echo "正在尝试在目录 '$SILLY_TAVERN_DIR' 中启动SillyTavern (server.js)..."
                    echo "按 Ctrl+C 停止程序。"
                    cd "$SILLY_TAVERN_DIR" && node server.js
                    local exit_code=$?
                    echo ""
                    echo "SillyTavern (node server.js) 已退出 (退出码: $exit_code)。"
                    cd "$SCRIPT_DIR" || exit 1
                else
                    echo "错误：未找到 'node' 命令。请确保 Node.js 已正确安装并位于 PATH 中。" >&2
                    echo "      你可以通过执行 'npm --version' 和 'node --version' 来检查。" >&2
                fi
            else
                echo "错误：未找到SillyTavern目录 '$SILLY_TAVERN_DIR' 或启动脚本 '$st_server_script'。" >&2
                echo "请先执行安装/更新SillyTavern (选项 7)。" >&2
            fi
            ;;
        8)
            install_sillytavern
            ;;
        0)
            echo "正在退出管理脚本..."
            return 1
            ;;
        *)
            echo "无效选项 '$option'。请输入菜单中显示的选项 [1-8, 0]。" >&2
            ;;
    esac

    if [[ "$option" != "0" ]]; then
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
