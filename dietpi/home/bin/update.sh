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
function install_debian_kept_back_pkgs {
    log_action "Checking for kept-back packages..."

    local list_kept_back
    list_kept_back=$(sudo apt-get upgrade --dry-run 2>/dev/null | sed -n 's/^ \([^ ]*\)/\1/p' | xargs)

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
log_info "Distribution: $DISTRO ($DISTRO_VERSION)"
log_info "Architecture: $ARCH"
echo
case $DISTRO in
    raspberrypi|debian|ubuntu|mint)
        update_debian
        ;;
    *)
        log_error "Unsupported distribution: $DISTRO"
        echo "Supported distributions: raspberrypi, debian, ubuntu, mint"
        exit 1
        ;;
esac
echo
log_success "System update completed!"
