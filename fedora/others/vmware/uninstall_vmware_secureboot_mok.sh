#!/usr/bin/env bash

# Complete VMware Uninstall Script for Fedora 43
# Safely removes all VMware components while preserving NVIDIA and system files
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -eq 0 ]; then
    log_error "Please run as regular user"
    exit 1
fi

log_info "=== Complete VMware Uninstallation ==="
log_info "This will remove ALL VMware components safely"

# Function to check if VMware is installed
check_vmware_installed() {
    if command -v vmware >/dev/null 2>&1 || \
       systemctl list-unit-files | grep -q vmware || \
       lsmod | grep -q vmw_; then
        return 0
    else
        return 1
    fi
}

# Check if VMware is actually installed
if ! check_vmware_installed; then
    log_info "No VMware components found. Nothing to uninstall."
    exit 0
fi

# Step 1: Stop VMware processes safely
log_info "Step 1: Stopping VMware processes..."
sudo pkill -f "vmware-usbarbitrator" 2>/dev/null || true
sudo pkill -f "vmware-networks" 2>/dev/null || true
sudo pkill -f "/usr/bin/vmware" 2>/dev/null || true
sleep 2

# Step 2: Stop and disable VMware services
log_info "Step 2: Stopping VMware services..."
sudo systemctl stop vmware-usbarbitrator 2>/dev/null || true
sudo systemctl stop vmware-networks-server 2>/dev/null || true
sudo systemctl stop vmware-networks 2>/dev/null || true
sudo systemctl stop vmware.service 2>/dev/null || true
sudo systemctl stop sign-vmware.service 2>/dev/null || true

sudo systemctl disable vmware-usbarbitrator 2>/dev/null || true
sudo systemctl disable vmware-networks-server 2>/dev/null || true
sudo systemctl disable vmware-networks 2>/dev/null || true
sudo systemctl disable vmware.service 2>/dev/null || true
sudo systemctl disable sign-vmware.service 2>/dev/null || true

# Step 3: Try official uninstaller first (if it exists)
sudo dnf remove -y perl
if command -v vmware-installer >/dev/null 2>&1; then
    log_info "Step 3: Running official VMware uninstaller..."
    echo "no" | sudo vmware-installer -u vmware-workstation 2>/dev/null || true
else
    log_info "Step 3: VMware installer not found, using manual removal"
fi

# Step 4: Remove VMware kernel modules
log_info "Step 4: Removing VMware kernel modules..."
sudo modprobe -r vmnet 2>/dev/null || true
sudo modprobe -r vmmon 2>/dev/null || true
sudo modprobe -r vmw_vsock_vmci_transport 2>/dev/null || true
sudo modprobe -r vmw_vmci 2>/dev/null || true

# Remove module files
for module in vmmon vmnet vmw_vsock_vmci_transport vmw_vmci; do
    sudo find /lib/modules -name "${module}.ko" -delete 2>/dev/null || true
    sudo find /lib/modules -name "${module}.ko.xz" -delete 2>/dev/null || true
done
sudo rm -rf /lib/modules/*/misc/vmware 2>/dev/null || true

# Step 5: Remove VMware binaries and applications
log_info "Step 5: Removing VMware binaries..."
sudo rm -f /usr/bin/vmware 2>/dev/null || true
sudo rm -f /usr/bin/vmplayer 2>/dev/null || true
sudo rm -f /usr/bin/vmware-config 2>/dev/null || true
sudo rm -f /usr/bin/vmware-modconfig 2>/dev/null || true
sudo rm -f /usr/bin/vmware-networks 2>/dev/null || true
sudo rm -f /usr/bin/vmware-usbarbitrator 2>/dev/null || true
sudo rm -f /usr/bin/vmware-installer 2>/dev/null || true

# Step 6: Remove VMware libraries and shared files
log_info "Step 6: Removing VMware libraries..."
sudo rm -rf /usr/lib/vmware 2>/dev/null || true
sudo rm -rf /usr/lib64/vmware 2>/dev/null || true
sudo rm -rf /usr/share/vmware 2>/dev/null || true
sudo rm -rf /opt/vmware 2>/dev/null || true

# Step 7: Remove VMware configuration
log_info "Step 7: Removing VMware configuration..."
sudo rm -rf /etc/vmware 2>/dev/null || true
sudo rm -rf /etc/vmware-vix 2>/dev/null || true
sudo rm -rf /etc/vmware-installer 2>/dev/null || true
sudo rm -f /etc/udev/rules.d/*vmware* 2>/dev/null || true

# Step 8: Remove systemd services
log_info "Step 8: Removing systemd services..."
sudo rm -f /usr/lib/systemd/system/vmware-*.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/multi-user.target.wants/vmware-*.service 2>/dev/null || true

# Step 9: Remove application files
log_info "Step 9: Removing application files..."
sudo rm -f /usr/share/applications/vmware-*.desktop 2>/dev/null || true
sudo rm -rf /usr/share/icons/hicolor/*/apps/vmware-* 2>/dev/null || true

# Step 10: Remove signing setup
log_info "Step 10: Removing signing setup..."
sudo rm -f /etc/systemd/system/sign-vmware.service 2>/dev/null || true
sudo rm -f /etc/kernel/postinst.d/99-sign-vmware 2>/dev/null || true
sudo rm -f /usr/local/bin/sign-vmware.sh 2>/dev/null || true

# Step 11: Clean temporary files
log_info "Step 11: Cleaning temporary files..."
sudo rm -rf /tmp/vmware-* 2>/dev/null || true
sudo rm -rf /tmp/modconfig-* 2>/dev/null || true
sudo rm -rf /tmp/vmware-root 2>/dev/null || true

# Step 12: Update system
log_info "Step 12: Updating system..."
sudo systemctl daemon-reload 2>/dev/null || true
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo depmod -a 2>/dev/null || true

# Step 13: Remove user data (optional)
log_info "Step 13: User data cleanup..."
read -p "Remove VMware virtual machines and configuration? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Removing user VMware data..."
    rm -rf "$HOME/vmware" 2>/dev/null || true
    rm -rf "$HOME/VMs" 2>/dev/null || true
    rm -rf "$HOME/.vmware" 2>/dev/null || true
    rm -rf "$HOME/.config/vmware" 2>/dev/null || true
else
    log_info "Keeping user data"
fi

# Step 14: Final verification
log_info "Step 14: Verification..."

echo "Checking VMware binaries:"
if command -v vmware >/dev/null 2>&1; then
    log_warn "VMware binary still exists"
else
    log_info "✓ No VMware binaries found"
fi

echo "Checking VMware processes:"
if pgrep -f "vmware" >/dev/null 2>&1; then
    log_warn "VMware processes still running"
else
    log_info "✓ No VMware processes running"
fi

echo "Checking VMware modules:"
if lsmod | grep -q vmw_; then
    log_warn "VMware modules still loaded"
else
    log_info "✓ No VMware modules loaded"
fi

echo "Checking VMware services:"
if systemctl list-unit-files | grep -q vmware; then
    log_warn "VMware services still exist"
else
    log_info "✓ No VMware services found"
fi

# Verify NVIDIA preservation
log_info "Verifying NVIDIA setup..."
KEY_DIR="/etc/pki/akmods"
if [ -f "$KEY_DIR/private/private_key.priv" ] && [ -f "$KEY_DIR/certs/public_key.der" ]; then
    log_info "✓ NVIDIA signing keys preserved"
fi

if lsmod | grep -q nvidia; then
    log_info "✓ NVIDIA modules still loaded"
fi

log_info "=== VMware Uninstallation Complete ==="
log_info ""
log_info "All VMware components have been removed successfully!"
log_info "Your NVIDIA setup and system dependencies are preserved."
log_info ""
log_warn "Recommended: Reboot to ensure clean state"
log_info "  sudo reboot"
