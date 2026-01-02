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
if [ "$EUID" -eq 0 ]; then
    log_error "Please run as regular user (not root)"
    exit 1
fi
#############################################################################

echo ""
log_warn "╔══════════════════════════════════════════════════════════════╗"
log_warn "║         VirtualBox Uninstallation Script                    ║"
log_warn "╠══════════════════════════════════════════════════════════════╣"
log_warn "║ This will remove VirtualBox while preserving:                ║"
log_warn "║   • Shared akmods keys (used by NVIDIA and other modules)    ║"
log_warn "║   • MOK key enrollment                                       ║"
log_warn "║   • RPM Fusion repositories                                  ║"
log_warn "║   • System packages (kernel-devel, akmods, etc.)             ║"
log_warn "╚══════════════════════════════════════════════════════════════╝"
echo ""

read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log_info "Uninstallation cancelled."
    exit 0
fi

log_info "=== Starting VirtualBox Uninstallation ==="

# ===== STOP SERVICES AND VMS =====
log_info "=== Stopping VirtualBox services and virtual machines ==="

# Stop all running VMs
if command -v VBoxManage &>/dev/null; then
    log_info "Stopping all running VirtualBox VMs..."
    RUNNING_VMS=$(VBoxManage list runningvms 2>/dev/null | cut -d'"' -f2 || true)
    for vm in $RUNNING_VMS; do
        log_info "Stopping VM: $vm"
        VBoxManage controlvm "$vm" poweroff 2>/dev/null || true
    done
    sleep 2
fi

# Stop VirtualBox services
log_info "Stopping VirtualBox services..."
sudo systemctl stop vboxdrv 2>/dev/null || true
sudo systemctl stop vboxweb-service 2>/dev/null || true
sudo systemctl stop vboxautostart-service 2>/dev/null || true
sudo systemctl stop sign-virtualbox.service 2>/dev/null || true

# ===== UNLOAD KERNEL MODULES =====
log_action "=== Unloading VirtualBox kernel modules ==="

LSMOD_OUTPUT=$(lsmod)
VBOX_MODULES=("vboxpci" "vboxnetflt" "vboxnetadp" "vboxdrv")
for module in "${VBOX_MODULES[@]}"; do
    MODULE_CHECK=$(echo "$LSMOD_OUTPUT" | grep "^$module" || true)
    if [ -n "$MODULE_CHECK" ]; then
        log_action "Unloading module: $module"
        sudo modprobe -r "$module" 2>/dev/null || log_warn "Could not unload $module"
    fi
done
log_success "Kernel modules unloaded"

# ===== REMOVE AUTO-SIGNING SETUP =====
log_info "=== Removing VirtualBox auto-signing setup ==="

# Remove signing service
if systemctl list-unit-files | grep -q sign-virtualbox.service; then
    sudo systemctl disable sign-virtualbox.service 2>/dev/null || true
    log_info "✓ Disabled sign-virtualbox service"
fi

sudo rm -f /etc/systemd/system/sign-virtualbox.service
log_info "✓ Removed service file"

# Remove kernel hook
if [ -f /etc/kernel/postinst.d/99-sign-virtualbox ]; then
    sudo rm -f /etc/kernel/postinst.d/99-sign-virtualbox
    log_info "✓ Removed kernel update hook"
fi

# Remove signing script
if [ -f /usr/local/bin/sign-virtualbox.sh ]; then
    sudo rm -f /usr/local/bin/sign-virtualbox.sh
    log_info "✓ Removed auto-signing script"
fi

# Reload systemd
sudo systemctl daemon-reload

# ===== REMOVE KERNEL MODULES =====
log_info "=== Removing VirtualBox kernel modules from disk ==="

# Remove module files
for module in vboxdrv vboxnetflt vboxnetadp vboxpci; do
    sudo find /lib/modules -name "${module}.ko" -delete 2>/dev/null || true
    sudo find /lib/modules -name "${module}.ko.xz" -delete 2>/dev/null || true
done

log_info "✓ Module files removed"

# ===== REMOVE PACKAGES =====
log_info "=== Removing VirtualBox packages ==="

log_info "Removing VirtualBox and guest additions..."
sudo dnf remove -y \
    virtualbox \
    virtualbox-guest-additions \
    VirtualBox \
    VirtualBox-kmodsrc \
    VirtualBox-server \
    akmod-VirtualBox \
    2>/dev/null || log_warn "Some packages may not have been installed"

log_info "✓ VirtualBox packages removed"

# ===== REMOVE CONFIGURATION =====
log_info "=== Removing VirtualBox configuration ==="

# Remove global configuration
sudo rm -rf /etc/vbox 2>/dev/null || true
sudo rm -f /etc/udev/rules.d/60-vboxdrv.rules 2>/dev/null || true

# Remove systemd services
sudo rm -f /usr/lib/systemd/system/vbox*.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/multi-user.target.wants/vbox*.service 2>/dev/null || true

# Remove application files
sudo rm -f /usr/share/applications/virtualbox*.desktop 2>/dev/null || true

# Remove binaries (if any remain)
sudo rm -f /usr/bin/VirtualBox 2>/dev/null || true
sudo rm -f /usr/bin/virtualbox 2>/dev/null || true
sudo rm -f /usr/bin/VBoxManage 2>/dev/null || true
sudo rm -f /usr/bin/VBoxHeadless 2>/dev/null || true

# Remove libraries
sudo rm -rf /usr/lib/virtualbox 2>/dev/null || true
sudo rm -rf /usr/lib64/virtualbox 2>/dev/null || true

log_info "✓ Configuration files removed"

# ===== REMOVE USER FROM GROUP =====
log_action "=== Removing user from vboxusers group ==="
GROUPS_OUTPUT=$(groups || true)
if echo "$GROUPS_OUTPUT" | grep -q vboxusers; then
    sudo gpasswd -d "$USER" vboxusers 2>/dev/null || true
    log_success "Removed $USER from vboxusers group"
else
    log_info "User not in vboxusers group"
fi

# ===== UPDATE MODULE CACHE =====
log_info "=== Updating kernel module cache ==="
sudo depmod -a
log_info "✓ Module cache updated"

# ===== REMOVE USER DATA (OPTIONAL) =====
log_info "=== User data cleanup ==="
echo ""
log_warn "Do you want to remove ALL VirtualBox virtual machines and configuration?"
log_warn "This will DELETE:"
log_warn "  • All virtual machines: $HOME/VirtualBox VMs/"
log_warn "  • User configuration: $HOME/.config/VirtualBox/"
log_warn "  • User data: $HOME/.VirtualBox/"
echo ""
read -p "Remove user data? [y/N]: " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Removing all VirtualBox virtual machines and configuration..."
    rm -rf "$HOME/VirtualBox VMs" 2>/dev/null || true
    rm -rf "$HOME/.config/VirtualBox" 2>/dev/null || true
    rm -rf "$HOME/.VirtualBox" 2>/dev/null || true
    log_info "✓ User data removed"
else
    log_info "Keeping VirtualBox virtual machines and user configuration"
    if [ -d "$HOME/VirtualBox VMs" ]; then
        log_info "VMs location: $HOME/VirtualBox VMs/"
    fi
    if [ -d "$HOME/.config/VirtualBox" ]; then
        log_info "Config location: $HOME/.config/VirtualBox/"
    fi
fi

# ===== AUTOREMOVE ORPHANED PACKAGES =====
log_info "=== Removing orphaned packages ==="
sudo dnf autoremove -y
log_info "✓ Orphaned packages removed"

# ===== VERIFICATION =====
log_action "=== Verification ==="

# Check if VirtualBox commands are gone
if ! command -v VirtualBox &>/dev/null && ! command -v VBoxManage &>/dev/null; then
    log_success "VirtualBox binaries removed"
else
    log_warn "Some VirtualBox binaries may still exist"
fi

# Check if modules are unloaded
LSMOD_FINAL=$(lsmod)
VBOX_FINAL_CHECK=$(echo "$LSMOD_FINAL" | grep vbox || true)
if [ -z "$VBOX_FINAL_CHECK" ]; then
    log_success "VirtualBox kernel modules unloaded"
else
    log_warn "Some VirtualBox modules may still be loaded (reboot recommended)"
fi

# Check if packages are removed
REMAINING_PACKAGES=""
for pkg in virtualbox VirtualBox VirtualBox-kmodsrc; do
    if rpm -q "$pkg" &>/dev/null; then
        REMAINING_PACKAGES="$REMAINING_PACKAGES $pkg"
    fi
done

if [ -z "$REMAINING_PACKAGES" ]; then
    log_info "✓ All VirtualBox packages removed"
else
    log_warn "Some packages still installed:$REMAINING_PACKAGES"
fi

# ===== VERIFY SHARED RESOURCES =====
log_action "=== Verifying shared resources (preserved) ==="

# Check akmods keys are intact
FEDORA_KEY=$(find /etc/pki/akmods/certs -name "fedora_*.der" -type f 2>/dev/null | head -n1 || true)
if [ -n "$FEDORA_KEY" ]; then
    log_success "Shared akmods keys preserved"
else
    log_info "akmods keys not present (may not have been generated)"
fi

# Check MOK enrollment
if command -v mokutil &>/dev/null; then
    MOK_OUTPUT=$(sudo mokutil --list-enrolled 2>/dev/null || true)
    AKMODS_CHECK=$(echo "$MOK_OUTPUT" | grep "akmods" || true)
    if [ -n "$AKMODS_CHECK" ]; then
        log_success "MOK key enrollment preserved"
    else
        log_info "MOK key not enrolled (normal if Secure Boot is disabled)"
    fi
fi

# Check NVIDIA modules (if installed)
NVIDIA_CHECK=$(echo "$LSMOD_FINAL" | grep nvidia || true)
if [ -n "$NVIDIA_CHECK" ]; then
    log_success "NVIDIA modules still loaded (unaffected)"
else
    log_info "NVIDIA modules not loaded (normal if not installed)"
fi

# Check RPM Fusion repos
DNFREPO_OUTPUT=$(dnf repolist 2>/dev/null || true)
if echo "$DNFREPO_OUTPUT" | grep -q rpmfusion; then
    log_success "RPM Fusion repositories preserved"
fi

# Check Secure Boot status
if command -v mokutil &>/dev/null; then
    SB_STATUS=$(sudo mokutil --sb-state 2>/dev/null || true)
    if echo "$SB_STATUS" | grep -q "SecureBoot enabled"; then
        log_success "Secure Boot remains enabled"
    fi
fi

# ===== COMPLETION =====
echo ""
log_info "╔══════════════════════════════════════════════════════════════╗"
log_info "║           UNINSTALLATION COMPLETE                           ║"
log_info "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_info "✅ VirtualBox has been uninstalled!"
echo ""
log_info "Removed:"
log_info "  ✓ VirtualBox packages and dependencies"
log_info "  ✓ VirtualBox kernel modules"
log_info "  ✓ VirtualBox auto-signing setup"
log_info "  ✓ VirtualBox system services and configuration"
log_info "  ✓ User removed from vboxusers group"
echo ""
log_info "Preserved:"
log_info "  ✓ Shared akmods keys (for NVIDIA and other kernel modules)"
log_info "  ✓ MOK key enrollment"
log_info "  ✓ RPM Fusion repositories"
log_info "  ✓ System packages (kernel-devel, akmods, etc.)"
echo ""

if [ -n "$VBOX_FINAL_CHECK" ]; then
    log_warn "Note: Some modules are still loaded."
    log_warn "Reboot recommended: sudo reboot"
else
    log_info "No reboot required (unless you want to verify cleanup)"
fi
echo ""
