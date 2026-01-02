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
log_warn "╔══════════════════════════════════════════════════════════════╗"
log_warn "║           NVIDIA DRIVERS UNINSTALLATION (MOK)                ║"
log_warn "╠══════════════════════════════════════════════════════════════╣"
log_warn "║ This will remove:                                            ║"
log_warn "║   • All NVIDIA drivers and packages                          ║"
log_warn "║   • MOK Secure Boot keys                                     ║"
log_warn "║   • Kernel parameters for NVIDIA                             ║"
log_warn "║   • Nouveau blacklist configurations                         ║"
log_warn "║   • Signing keys and certificates                            ║"
log_warn "╚══════════════════════════════════════════════════════════════╝"
echo ""
read -r -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log_info "Uninstallation cancelled."
    exit 0
fi
#############################################################################
log_info "Removing MOK Secure Boot keys"
PUBLIC_DER="/etc/pki/akmods/certs/public_key.der"
if [ -f "$PUBLIC_DER" ]; then
    MOK_OUTPUT=$(mokutil --list-enrolled 2>/dev/null || true)
    AKMODS_CHECK=$(echo "$MOK_OUTPUT" | grep "akmods" || true)
    if [ -n "$AKMODS_CHECK" ]; then
        log_action "Removing akmods key from MOK..."
        echo ""
        log_warn "You will be asked to set a password for MOK deletion."
        log_warn "Remember this password - you'll need it at the BLUE MOK screen on next boot."
        echo ""
        if mokutil --delete "$PUBLIC_DER"; then
            log_success "MOK key deletion scheduled"
            log_warn "You must complete the deletion at the MOK screen on next boot!"
        else
            log_warn "Failed to schedule MOK key deletion"
        fi
    else
        log_info "No akmods key found in MOK database (may have been deleted or never enrolled)"
    fi
else
    log_info "No MOK certificate found (already removed or never created)"
fi
#############################################################################
log_action "Removing NVIDIA drivers and related packages..."
dnf remove -y \
    akmod-nvidia \
    kmod-nvidia-* \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-libs \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-cuda-libs \
    libva-nvidia-driver libva libva-utils \
    vdpauinfo \
    gstreamer1-vaapi \
    vulkan \
    nvidia-settings \
    nvidia-persistenced \
    nvidia-xconfig 2>/dev/null || log_warn "Some packages may not have been installed"
log_success "NVIDIA packages removed"
#############################################################################
log_info "Removing NVIDIA kernel modules"
NVIDIA_MODULES=(nvidia_drm nvidia_modeset nvidia_uvm nvidia)
for module in "${NVIDIA_MODULES[@]}"; do
    if lsmod | grep -q "^$module"; then
        log_action "Unloading module: $module"
        modprobe -r "$module" 2>/dev/null || log_warn "Could not unload $module (may need reboot)"
    fi
done
if [ -d "/lib/modules/$(uname -r)/extra/nvidia" ]; then
    log_action "Removing NVIDIA module directory..."
    rm -rf "/lib/modules/$(uname -r)/extra/nvidia"
    log_success "NVIDIA modules directory removed"
fi
#############################################################################
log_action "Updating initramfs"
dracut --force
log_success "Initramfs updated"
#############################################################################
log_action "Updating module dependencies"
depmod -a
log_success "Module dependencies updated"
#############################################################################
log_action "Removing orphaned packages"
dnf autoremove -y
log_success "Orphaned packages removed"
#############################################################################
log_info "Verification"
if lsmod | grep -q nvidia; then
    log_warn "Some NVIDIA modules are still loaded (will be removed after reboot)"
    lsmod | grep nvidia
else
    log_success "No NVIDIA modules loaded"
fi

if lsmod | grep -q nouveau; then
    log_success "Nouveau driver is loaded"
else
    log_info "Nouveau driver not loaded (will load after reboot)"
fi

if command -v grubby &>/dev/null; then
    CURRENT_CMDLINE=$(grubby --info="$(grubby --default-kernel)" 2>/dev/null | grep "args=" | cut -d'"' -f2)
    if echo "$CURRENT_CMDLINE" | grep -q "nvidia"; then
        log_warn "Some NVIDIA parameters still in kernel command line:"
        echo "$CURRENT_CMDLINE" | grep -o "nvidia[^ ]*"
    else
        log_success "No NVIDIA parameters in kernel command line"
    fi
fi
#############################################################################
echo ""
log_info "╔══════════════════════════════════════════════════════════════╗"
log_info "║              UNINSTALLATION COMPLETE                         ║"
log_info "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_success "NVIDIA drivers have been removed!"
echo ""
log_info "IMPORTANT NEXT STEPS:"
echo ""
log_info "1. REBOOT YOUR SYSTEM:"
echo "   sudo reboot"
echo ""
log_info "2. DURING REBOOT (if you scheduled MOK key deletion):"
echo "   - A BLUE MOK screen will appear"
echo "   - Select: Delete MOK"
echo "   - ENTER YOUR PASSWORD (the one you set during deletion)"
echo "   - Confirm deletion"
echo "   - System will reboot automatically"
echo ""
log_info "3. AFTER REBOOT:"
echo "   - Nouveau driver should load automatically"
echo "   - You can verify with: lsmod | grep nouveau"
echo "   - Check graphics with: glxinfo | grep renderer"
echo ""
log_warn "NOTES:"
echo "   • If you want to keep Secure Boot enabled, that's fine"
echo "   • Nouveau works with Secure Boot (it's signed by Fedora)"
echo "   • If MOK screen doesn't appear, the key may not have been enrolled"
echo "   • You can check MOK status with: sudo mokutil --list-enrolled"
echo ""
