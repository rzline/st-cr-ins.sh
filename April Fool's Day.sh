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
    echo "üüüüF${2}"
    exit ${1}
}

detect_system() {
    echo "üüüüŒnüüüü‹«..."
    
    if [[ -n "$PREFIX" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        IS_TERMUX=true
        echo "üüüü“žTermuxüü‹«"
    else
        IS_TERMUX=false
        
        if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -q -i 'musl'; then
            IS_MUSL=true
            echo "üüüü“žMUSL Linuxüü‹«"
        else
            IS_MUSL=false
            echo "üüüü“žüüyLinuxüü‹«(glibc)"
        fi
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armv8l) handle_error 1 "üü•sŽxŽ32ˆÊARM‰Ëüü ($ARCH)" ;;
        *) handle_error 1 "•sŽxŽ“IŒnüü‰Ëüü: $ARCH" ;;
    esac
    echo "üüüü“ž‰Ëüü: $ARCH"
    
    if [ "$IS_TERMUX" = true ] && [ "$ARCH" != "aarch64" ]; then
        handle_error 1 "Termuxüü‹«üüŽxŽaarch64‰Ëüü"
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
        echo "Œx: –¢üüüü“žŽxŽ“I•ïŠÇ—ŠíC«’µüüˆËüüˆÀ‘•"
        PACKAGE_MANAGER="unknown"
        INSTALL_CMD=""
    fi
    
    [ -n "$PACKAGE_MANAGER" ] && echo "Žg—p•ïŠÇ—Ší: $PACKAGE_MANAGER"
}

install_dependencies() {
    echo "üüüü›óˆÀ‘•ˆËüü..."
    local dependencies=("curl" "unzip" "ldd")
    local missing_deps=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo "Š—LˆËüü›ßˆÀ‘•"
        return 0
    fi
    
    if [ "$PACKAGE_MANAGER" = "unknown" ] || [ -z "$INSTALL_CMD" ]; then
        handle_error 1 "ãž­ˆÈ‰ºˆËüüC’AÙ–@Ž©üüˆÀ‘•: ${missing_deps[*]}"
    fi
    
    echo "ˆÀ‘•ãžŽ¸“IˆËüü: ${missing_deps[*]}"
    
    case "$PACKAGE_MANAGER" in
        apt|pkg) apt update || pkg update ;;
        pacman) pacman -Sy ;;
        zypper) zypper refresh ;;
        apk) apk update ;;
    esac
    
    if ! $INSTALL_CMD "${missing_deps[@]}"; then
        handle_error 1 "ˆËüüˆÀ‘•Ž¸üüCüüŽèüüˆÀ‘•: ${missing_deps[*]}"
    fi
    
    for dep in "${missing_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error 1 "ˆËüü $dep ˆÀ‘•Ž¸üüCüüŽèüüˆÀ‘•"
        fi
    done
    
    echo "ˆËüüˆÀ‘•Š®¬"
}

check_version() {
    echo "üüüüüüŒ”Å–{..."
    
    if [ ! -d "$TARGET_DIR" ]; then
        echo "–¢üüüü“ž›ßˆÀ‘•”Å–{C«üüsŽñŽŸˆÀ‘•"
        return 0
    fi
    
    if [ ! -f "$VERSION_FILE" ]; then
        echo "–¢Q“ž”Å–{M‘§•¶ŒC«dVˆÀ‘•ÅV”Å–{"
        return 0
    fi
    
    LOCAL_VERSION=$(cat "$VERSION_FILE")
    echo "“–‘O›ßˆÀ‘•”Å–{: $LOCAL_VERSION"
    
    echo "³ÝüüüüÅV”Å–{..."
    
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local api_url="$GH_API_URL"
    local use_proxy=false
    
    if [ -n "$country_code" ] && [ "$country_code" = "CN" ]; then
        echo "üüüü“ž’†‘‘åüüIPC«Žg—p‘ã—üüŽæ”Å–{M‘§"
        api_url="${GH_PROXY}${GH_API_URL}"
        use_proxy=true
    fi
    
    local latest_info=$(curl -s --connect-timeout 10 "$api_url")
    if [ -z "$latest_info" ]; then
        echo "Ù–@üüŽæÅV”Å–{M‘§C«•ÛŽ“–‘O”Å–{"
        return 1
    fi
    
    LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    fi
    
    if [ -z "$LATEST_VERSION" ]; then
        echo "‰ðÍ”Å–{M‘§Ž¸üüC«•ÛŽ“–‘O”Å–{"
        return 1
    fi
    
    echo "ÅV”Å–{: $LATEST_VERSION"
    
    if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
        echo "›ß¥ÅV”Å–{CÙŽùXV"
        read -p "¥”Ûüü§dVˆÀ‘•H(y/N): " force_update
        if [[ "$force_update" =~ ^[Yy]$ ]]; then
            echo "«üü§dVˆÀ‘•..."
            return 0
        else
            return 1
        fi
    else
        echo "üüüüV”Å–{C«XV“ž $LATEST_VERSION"
        return 0
    fi
}

setup_download_url() {
    echo "üüüüIP’n—ˆÊ’u..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "üüüü“ž‘‰Æ‘ãüü: $country_code"
        
        if [ "$country_code" = "CN" ]; then
            echo "üüüü“ž’†‘‘åüüIPCàÒüüüü—pGitHub‘ã—: $GH_PROXY"
            read -p "¥”Û‹Ö—pGitHub‘ã—H(y/N): " disable_proxy
            
            if [[ "$disable_proxy" =~ ^[Yy]$ ]]; then
                GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
                echo "›ß‹Ö—pGitHub‘ã—C«’¼üüGitHub"
            else
                GH_DOWNLOAD_URL="${GH_PROXY}${GH_DOWNLOAD_URL_BASE}"
                echo "Žg—pGitHub‘ã—: $GH_PROXY"
            fi
        else
            GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
            echo "”ñ’†‘‘åüüIPC•sŽg—pGitHub‘ã—"
        fi
    else
        echo "Ù–@üüüüIP’n—ˆÊ’uC•sŽg—pGitHub‘ã—"
        GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        DOWNLOAD_FILENAME="$SOFTWARE_NAME-android-aarch64.zip"
    elif [ "$IS_MUSL" = true ]; then
        DOWNLOAD_FILENAME="$SOFTWARE_NAME-musllinux-$ARCH.zip"
        echo "üüüü“žmuslüü‹«CŽ©üüüüüümusl”Å–{"
    else
        echo "üüüü“žglibcüü‹«"
        echo "üüüüüü—v‰ºüü“I“ñüü§•¶ŒüüŒ^:"
        echo "glibc”Å–{†•s‘«2.38“IŒnüüüüŽg—pmusl”Å–{"
        echo "glibc”Å–{†‰ÂŽg—p 'ldd --version' –½—ßüüŠÅ"
        echo "1) glibc ”Å–{ (üüy Linux ”Å–{C„ä¦)"
        echo "2) musl ”Å–{ (üü—p˜° Alpine “™Žg—p musl “IŒnüü)"
        read -p "üüüü“üüüüü [1-2] (àÒüü1): " libc_choice
        
        case "${libc_choice:-1}" in
            2)
                DOWNLOAD_FILENAME="$SOFTWARE_NAME-musllinux-$ARCH.zip"
                echo "›ßüüüü musl ”Å–{"
                ;;
            *)
                DOWNLOAD_FILENAME="$SOFTWARE_NAME-linux-$ARCH.zip"
                echo "›ßüüüü glibc ”Å–{"
                ;;
        esac
    fi
    
    echo "Žg—p”Å–{: $DOWNLOAD_FILENAME"
}

download_and_install() {
    echo "yüü–Úüü–Úüü..."
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR"
        echo "üüŒš–Úüü–Úüü: $TARGET_DIR"
    else
        echo "–Úüü–Úüü›ß‘¶ÝC«•¢á³düü•¶Œ"
    fi
    
    local download_url="$GH_DOWNLOAD_URL/$DOWNLOAD_FILENAME"
    local download_path="$TARGET_DIR/$DOWNLOAD_FILENAME"
    echo "‰ºüü: $download_url"
    
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
        
        echo "‰ºüüŽ¸üüCüüüüdüü..."
        rm -f "$download_path"
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $max_retries ]; then
            echo "«Ý $wait_time •b@düü ($retry_count/$max_retries)..."
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            handle_error 1 "‰ºüüŽ¸üü: $download_url"
        fi
    done
    
    echo "‰ðüü•¶Œ..."
    if ! unzip -o "$download_path" -d "$TARGET_DIR"; then
        rm -f "$download_path"
        handle_error 1 "‰ðüüŽ¸üü: $download_path"
    fi
    
    rm -f "$download_path"
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
    fi
    
    if [ -n "$LATEST_VERSION" ]; then
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        echo "”Å–{M‘§›ß•Û‘¶: $LATEST_VERSION"
    fi
    
    echo "ˆÀ‘•Š®¬I"
    echo "===================="
    echo "$SOFTWARE_NAME ›ßˆÀ‘•“ž: $TARGET_DIR"
    echo "üü‰ÂˆÈüüs: $TARGET_DIR/$SOFTWARE_NAME —ˆüüs’ö˜"
    echo "===================="
}

open_port() {
    echo "³Ýüüüüüü•ú’[Œû $PORT..."
    
    if [ "$EUID" -ne 0 ] && [ "$IS_TERMUX" = false ]; then
        echo "’ˆÓ: Žù—vŽg—prootüüŒÀ—ˆüü•ú’[ŒûC“–‘O”ñroot—püü"
        read -p "¥”ÛüüüüŽg—psudoüü•ú’[ŒûH(y/N): " use_sudo
        if [[ ! "$use_sudo" =~ ^[Yy]$ ]]; then
            echo "’µüü’[Œûüü•úCüüŽèüüüü•ú’[Œû $PORT"
            return
        fi
        HAS_SUDO=true
    else
        HAS_SUDO=false
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        echo "Termuxüü‹«ÙŽùŽèüüüü•ú’[ŒûCüü—p«Ž©üüŽg—p $PORT ’[Œû"
        return
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo "üüüü“žfirewalld•žüü"
        if [ "$HAS_SUDO" = true ]; then
            sudo firewall-cmd --zone=public --add-port=$PORT/tcp --permanent && \
            sudo firewall-cmd --reload && \
            echo "›ß¬Œ÷üü•ú’[Œû $PORT (firewalld)"
        else
            firewall-cmd --zone=public --add-port=$PORT/tcp --permanent && \
            firewall-cmd --reload && \
            echo "›ß¬Œ÷üü•ú’[Œû $PORT (firewalld)"
        fi
    elif command -v ufw >/dev/null 2>&1; then
        echo "üüüü“žufw•žüü"
        if [ "$HAS_SUDO" = true ]; then
            sudo ufw allow $PORT/tcp && \
            sudo ufw reload && \
            echo "›ß¬Œ÷üü•ú’[Œû $PORT (ufw)"
        else
            ufw allow $PORT/tcp && \
            ufw reload && \
            echo "›ß¬Œ÷üü•ú’[Œû $PORT (ufw)"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        echo "Žg—piptablesüü•ú’[Œû"
        if [ "$HAS_SUDO" = true ]; then
            sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT && \
            echo "›ßŽg—piptablesüü•ú’[Œû $PORT"
            echo "’ˆÓFüüüü’u‰Â”\•s‰ïÝŒnüüdüü@•Û—¯Cüülüü«‘´“Y‰Á“žŒnüüüüüü‹r–{’†"
        else
            iptables -A INPUT -p tcp --dport $PORT -j ACCEPT && \
            echo "›ßŽg—piptablesüü•ú’[Œû $PORT"
            echo "’ˆÓFüüüü’u‰Â”\•s‰ïÝŒnüüdüü@•Û—¯Cüülüü«‘´“Y‰Á“žŒnüüüüüü‹r–{’†"
        fi
    else
        echo "–¢üüüü“žŽxŽ“I–h‰Îüü•žüüCüüŽèüüüü•ú’[Œû $PORT"
    fi
    
    if command -v getenforce >/dev/null 2>&1; then
        selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            echo "üüüü“žSELinuxüü˜°ŠˆüüóüüCüüüü”z’uSELinuxô—ª..."
            if command -v semanage >/dev/null 2>&1; then
                if [ "$HAS_SUDO" = true ]; then
                    sudo semanage port -a -t http_port_t -p tcp $PORT || \
                    echo "SELinux’[Œû”z’u–¢¬Œ÷C‰Â”\Žù—vŽèüü”z’u"
                else
                    semanage port -a -t http_port_t -p tcp $PORT || \
                    echo "SELinux’[Œû”z’u–¢¬Œ÷C‰Â”\Žù—vŽèüü”z’u"
                fi
            else
                echo "–¢Q“žsemanage–½—ßCÙ–@Ž©üü”z’uSELinuxô—ª"
                echo "”@‹ö“žüüŒÀüüüüCüüŽèüü”z’uSELinuxˆòüü’ö˜Žg—p’[Œû $PORT"
            fi
        fi
    fi
    
    echo "’[Œû $PORT ”z’uŠ®¬"
}

run_program() {
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        read -p "¥”Û—§‘¦üüs $SOFTWARE_NAMEH(y/N): " run_now
        if [[ "$run_now" =~ ^[Yy]$ ]]; then
            echo "³Ýüüüü $SOFTWARE_NAME..."
            cd "$TARGET_DIR" && ./"$SOFTWARE_NAME"
        else
            echo "üü‰ÂˆÈâc@’Êüüüüs: $TARGET_DIR/$SOFTWARE_NAME —ˆüüs’ö˜"
        fi
    else
        echo "Œx: –¢Q“ž‰Âüüs•¶Œ $TARGET_DIR/$SOFTWARE_NAME"
    fi
}

main() {
    echo "üüŽnˆÀ‘• $SOFTWARE_NAME..."
    detect_system
    install_dependencies
    
    if ! check_version; then
        echo "›ßŽæÁˆÀ‘•/XV‘€ì"
        exit 0
    fi
    
    setup_download_url
    download_and_install
    open_port
    run_program
}

main