#!/usr/bin/env bash
#############################################################################
set -e          # Exit on error
set -u          # Error on undefined variables
set -o pipefail # Pipe failures propagate
#############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
#############################################################################
INFO_MARK="${MAGENTA}ℹ${NC}"
ACTION_MARK="${BLUE}➜${NC}"
WARNING_MARK="${YELLOW}⚠${NC}"
SUCCESS_MARK="${GREEN}✓${NC}"
ERROR_MARK="${RED}✗${NC}"
#############################################################################
log_info() { echo -e "${INFO_MARK} ${MAGENTA}[INFO]${NC} $*"; }
log_warn() { echo -e "${WARNING_MARK} ${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${ERROR_MARK} ${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${SUCCESS_MARK} ${GREEN}[SUCCESS]${NC} $*"; }
log_action() { echo -e "${ACTION_MARK} ${BLUE}[ACTION]${NC} $*"; }
#############################################################################
[[ $EUID -eq 0 ]] && log_error "Script cannot be run by root" && exit 1
#############################################################################
export ACCEPT_EULA=Y
#############################################################################
ARCH=$(uname -m)
DISTRO=$( (source /etc/os-release && echo "$ID") 2>/dev/null || echo "unknown")
DISTRO_VERSION=$( (source /etc/os-release && echo "$VERSION_ID") 2>/dev/null || echo "unknown")
#############################################################################
if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null ||
   [[ "$(cat /proc/device-tree/model 2>/dev/null)" == *"Raspberry"* ]] ||
   [[ -f /etc/rpi-issue ]] ||
   [[ -f /boot/issue.txt && "$(cat /proc/device-tree/model 2>/dev/null)" == *"Raspberry"* ]]; then
    DISTRO="raspberrypi"
else
    case "$DISTRO" in
        ubuntu|kubuntu|lubuntu|xubuntu) DISTRO="ubuntu" ;;
        linuxmint) DISTRO="mint" ;;
    esac
fi
#############################################################################
case "$ARCH" in
    x86_64) REMOTE_DOCKER_COMPOSE="docker-compose-linux-x86_64" ;;
    aarch64|arm*) REMOTE_DOCKER_COMPOSE="docker-compose-linux-aarch64" ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        echo "This script only supports x86_64 and ARM systems."
        exit 1
        ;;
esac
#############################################################################
function install_debian_kept_back_pkgs {
    log_action "Checking for kept-back packages..."

    local list_kept_back
    list_kept_back=$(sudo apt-get upgrade --dry-run 2>/dev/null | sed -n 's/^ \([^ ]*\)/\1/p' | tr '\n' ' ')

    if [ -n "$list_kept_back" ]; then
        log_action "Installing kept-back packages: $list_kept_back"
        sudo apt-get install -y "$list_kept_back"
    else
        log_success "No kept-back packages found"
    fi
}
#############################################################################
function update_debian {
    log_action "Updating $DISTRO packages..."

    sudo apt update
    install_debian_kept_back_pkgs
    sudo apt-get install -y -f
    sudo apt-get upgrade -y
    sudo apt-get dist-upgrade -y
    sudo apt-get full-upgrade -y
    sudo apt-get autoremove -y --purge
    sudo apt-get clean
}
#############################################################################
function update_docker_compose {
    log_action "Checking docker-compose updates..."

    local local_path
    local plugin_path
    local latest_version
    local current_version

    local_path="${HOME}/bin/docker-compose"
    plugin_path="/usr/libexec/docker/cli-plugins/docker-compose"
    latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | sed -Ene '/^ *"tag_name": *"(v.+)",$/s//\1/p')

    if [[ -f $local_path ]]; then
        current_version=$($local_path --version 2>/dev/null | awk '{print $4}' || echo "unknown")
    elif [[ -f $plugin_path ]]; then
        current_version=$($plugin_path --version 2>/dev/null | awk '{print $4}' || echo "unknown")
    else
        current_version="not installed"
    fi

    if [[ -z "$latest_version" ]]; then
        log_error "Failed to fetch latest docker-compose version"
        return 1
    fi

    if [[ $current_version != "$latest_version" ]]; then
        log_action "Updating docker-compose $current_version -> $latest_version"

        if [[ -f $local_path ]]; then
            sudo rm -rf "$local_path"
        fi
        if [[ -f $plugin_path ]]; then
            sudo rm -rf "$plugin_path"
        fi

        curl -L "https://github.com/docker/compose/releases/download/$latest_version/${REMOTE_DOCKER_COMPOSE}" -o "$local_path"
        if [[ $? -eq 0 ]]; then
            sudo chmod 755 "$local_path"
            sudo mkdir -p "$(dirname "$plugin_path")"
            sudo cp "$local_path" "$plugin_path"
            sudo chmod 755 "$plugin_path"
            log_success "docker-compose updated to $latest_version"
        else
            log_error "Failed to download docker-compose"
            return 1
        fi
    else
        log_success "docker-compose is already at latest version $latest_version"
    fi
}
#############################################################################
log_info "Distribution: $DISTRO ($DISTRO_VERSION)"
log_info "Architecture: $ARCH"
echo
case $DISTRO in
    raspberrypi|debian|ubuntu|mint)
        update_debian
        update_docker_compose
        ;;
    *)
        log_error "Unsupported distribution: $DISTRO"
        echo "Supported distributions: raspberrypi, debian, ubuntu, mint"
        exit 1
        ;;
esac
echo
log_success "System update completed!"
