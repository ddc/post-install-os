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
[[ $EUID -ne 0 ]] && log_error "Script should be run by root" && exit 1
#############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         NVIDIA Installation with Fedora MOK                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
#############################################################################
log_action "Checking Secure Boot status..."
SB_STATUS=$(mokutil --sb-state 2>/dev/null || true)
if ! echo "$SB_STATUS" | grep -q "SecureBoot enabled"; then
    log_error "Secure Boot is NOT enabled!"
    log_error "Please enable Secure Boot in BIOS/UEFI first, then run this script."
    log_info ""
    log_info "Steps:"
    log_info "1. Reboot and enter BIOS/UEFI (usually F2, F12, Del, or Esc)"
    log_info "2. Find Secure Boot setting and enable it"
    log_info "3. Save changes and boot back into Fedora"
    log_info "4. Run this script again"
    exit 1
fi
log_success "Secure Boot is enabled"
#############################################################################
log_action "Enabling RPM Fusion repositories"
sudo dnf config-manager setopt rpmfusion-nonfree-nvidia-driver.enabled=1
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    log_action "Installing RPM Fusion FREE repository..."
    sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    log_success "RPM Fusion FREE installed"
fi
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    log_action "Installing RPM Fusion NONFREE repository..."
    sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
        log_success "RPM Fusion NONFREE installed"
fi
sudo dnf clean all -y
sudo dnf makecache -y
#############################################################################
log_action "Installing NVIDIA drivers and Secure Boot tools..."
sudo dnf install -y \
  akmods kmodtool mokutil openssl \
  akmod-nvidia \
  xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs \
  libva-nvidia-driver libva libva-utils \
  vdpauinfo \
  gstreamer1-vaapi \
  vulkan
log_success "NVIDIA drivers and tools installed"
#############################################################################
log_action "Installing v4l2loopback for virtual camera"
sudo dnf install -y v4l2loopback
log_success "v4l2loopback package installed"
#############################################################################
log_action "Building kernel modules with akmods (NVIDIA + v4l2loopback)"
sudo akmods --force
log_success "Kernel modules built and signed"
#############################################################################
log_action "Configuring v4l2loopback to load at boot"
echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf > /dev/null
log_info "Note: v4l2loopback will load automatically after MOK enrollment and reboot"
#############################################################################
log_action "Generating keys with default values"
kmodgenca -a
##############################################################################
log_action "=== Checking MOK enrollment status ==="
MOK_OUTPUT=$(mokutil --list-enrolled 2>/dev/null || true)
AKMODS_CHECK=$(echo "$MOK_OUTPUT" | grep "akmods" || true)
if [ -n "$AKMODS_CHECK" ]; then
    log_success "akmods key is already enrolled in MOK"
    log_info "Skipping MOK enrollment (key is ready to use)"
    log_info "Enrolled key details:"
    echo "$MOK_OUTPUT" | grep -A3 "akmods" | head -4
else
    PUBLIC_DER="/etc/pki/akmods/certs/public_key.der"

    log_info "akmods key is not yet enrolled - preparing MOK enrollment"
    echo ""
    log_info "╔══════════════════════════════════════════════════════════════╗"
    log_info "║                  IMPORTANT: MOK PASSWORD                     ║"
    log_info "╠══════════════════════════════════════════════════════════════╣"
    log_info "║ You will now set a password for Secure Boot key enrollment.  ║"
    log_info "║                                                              ║"
    log_info "║ Choose a SIMPLE password you'll remember:                    ║"
    log_info "║   • Example: nvidia                                          ║"
    log_info "║                                                              ║"
    log_info "║ You will use this SAME password during boot                  ║"
    log_info "║ at the BLUE MOK screen.                                      ║"
    log_info "║                                                              ║"
    log_info "║ Press Enter to continue and set your password...             ║"
    log_info "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    read -r -p ""

    log_action "Importing key to MOK database..."
    echo ""
    log_action "Setting MOK password (you'll enter it twice)..."
    echo ""

    if mokutil --import "$PUBLIC_DER"; then
        log_info ""
        log_success "PASSWORD SET SUCCESSFULLY!"
        log_info ""
        log_info "IMPORTANT: Remember your password!"
        log_info "You'll need it during boot at the BLUE MOK screen."
    else
        log_warn "Key import failed or was cancelled"
        log_info "You can try again later with: mokutil --import $PUBLIC_DER"
        exit 1
    fi

    log_info "MOK enrollment scheduled:"
    MOK_NEW=$(mokutil --list-new 2>/dev/null || true)
    if [ -n "$MOK_NEW" ]; then
        echo "$MOK_NEW" | head -10
    else
        echo "  Check status after reboot"
    fi
fi
##############################################################################
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 INSTALLATION COMPLETE                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_success "NVIDIA installation with MOK Secure Boot is ready!"
log_info "NEXT STEPS:"
echo "1. sudo reboot"
echo ""
log_info "DURING REBOOT - IMPORTANT:"
echo "   - A BLUE MOK screen will appear"
echo "   - Press any key when prompted"
echo "   - Select: Enroll MOK"
echo "   - Select: Continue"
echo "   - ENTER YOUR PASSWORD (the one you just set)"
echo "   - Select: Yes"
echo "   - System will reboot automatically"
echo ""
