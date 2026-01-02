#!/usr/bin/env bash

# VMware Workstation Installer with SecureBoot Signing for Fedora 43
set -e

# Global Variables
VMWARE_BUNDLE="/home/ddc/Programs/_Installs_/VMware-Workstation-Full-17.6.4-24832109.x86_64.bundle"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -eq 0 ]; then
    log_error "Please run as regular user"
    exit 1
fi

log_info "Starting VMware Workstation installation with SecureBoot signing..."
log_info "Using bundle: $VMWARE_BUNDLE"

# Step 1: Verify VMware bundle exists
log_info "Step 1: Verifying VMware bundle..."
if [ ! -f "$VMWARE_BUNDLE" ]; then
    log_error "VMware bundle not found: $VMWARE_BUNDLE"
    log_info "Please update the VMWARE_BUNDLE variable in the script with the correct path"
    exit 1
fi

if [ ! -x "$VMWARE_BUNDLE" ]; then
    log_info "Making bundle executable..."
    chmod +x "$VMWARE_BUNDLE"
fi

# Step 2: Install VMware Workstation
log_info "Step 2: Installing VMware Workstation..."
sudo "$VMWARE_BUNDLE" --console --eulas-agreed --required

# Step 3: Install dependencies
log_info "Step 3: Installing dependencies..."
sudo dnf install -y \
    kernel-devel \
    kernel-headers \
    gcc \
    make \
    perl \
    elfutils-libelf-devel

# Step 4: Build VMware kernel modules
log_info "Step 4: Building VMware kernel modules..."
sudo vmware-modconfig --console --install-all

# Step 5: Set up VMware signing
log_info "Step 5: Setting up VMware SecureBoot signing..."

KEY_DIR="/etc/pki/akmods"
PRIVATE_KEY="$KEY_DIR/private/private_key.priv"
PUBLIC_KEY="$KEY_DIR/certs/public_key.der"

# Verify signing keys exist
if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    log_error "Signing keys not found!"
    log_info "Expected private key: $PRIVATE_KEY"
    log_info "Expected public key: $PUBLIC_KEY"
    log_info "Please ensure your NVIDIA keys are properly set up"
    exit 1
fi

log_info "Using existing signing keys:"
log_info "  Private: $PRIVATE_KEY"
log_info "  Public:  $PUBLIC_KEY"

# Create VMware signing script
sudo tee /usr/local/bin/sign-vmware.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
KEY_DIR="/etc/pki/akmods"
PRIVATE_KEY="$KEY_DIR/private/private_key.priv"
PUBLIC_KEY="$KEY_DIR/certs/public_key.der"

# VMware modules
MODULES=("vmmon" "vmnet")

SIGN_TOOL="/usr/src/kernels/$(uname -r)/scripts/sign-file"

# Check if sign-file tool exists
if [ ! -f "$SIGN_TOOL" ]; then
    echo "Error: sign-file tool not found at $SIGN_TOOL"
    echo "Please install kernel-devel package"
    exit 1
fi

for module in "${MODULES[@]}"; do
    # Try multiple possible locations
    PATHS=(
        "/lib/modules/$(uname -r)/misc/${module}.ko"
        "/lib/modules/$(uname -r)/misc/${module}.ko.xz"
        "/lib/modules/$(uname -r)/extra/${module}.ko"
        "/lib/modules/$(uname -r)/extra/${module}.ko.xz"
    )

    MODULE_FOUND=false

    for MODULE_PATH in "${PATHS[@]}"; do
        if [ -f "$MODULE_PATH" ]; then
            echo "Signing VMware module: $module at $MODULE_PATH"
            "$SIGN_TOOL" sha256 "$PRIVATE_KEY" "$PUBLIC_KEY" "$MODULE_PATH"
            echo "✓ Signed: $module"
            MODULE_FOUND=true
            break
        fi
    done

    if [ "$MODULE_FOUND" = false ]; then
        echo "Warning: Module $module not found in standard locations"
    fi
done

# Also check VMware's own directory
VMWARE_MOD_DIR="/lib/modules/$(uname -r)/misc/vmware"
if [ -d "$VMWARE_MOD_DIR" ]; then
    for module in "${MODULES[@]}"; do
        MODULE_PATH="$VMWARE_MOD_DIR/${module}.ko"
        if [ -f "$MODULE_PATH" ]; then
            echo "Signing VMware module: $module at $MODULE_PATH"
            "$SIGN_TOOL" sha256 "$PRIVATE_KEY" "$PUBLIC_KEY" "$MODULE_PATH"
            echo "✓ Signed: $module"
        fi
    done
fi

# Update module dependencies
depmod -a

echo "VMware module signing completed for kernel: $(uname -r)"
EOF

sudo chmod +x /usr/local/bin/sign-vmware.sh

# Create systemd service for VMware
sudo tee /etc/systemd/system/sign-vmware.service > /dev/null << 'EOF'
[Unit]
Description=Sign VMware kernel modules
After=akmods.service
Wants=akmods.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sign-vmware.sh
RemainAfterExit=yes
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF

# Create kernel hook for VMware
sudo tee /etc/kernel/postinst.d/99-sign-vmware << 'EOF'
#!/usr/bin/env bash
# Trigger VMware signing after kernel install
/usr/local/bin/sign-vmware.sh
EOF

sudo chmod +x /etc/kernel/postinst.d/99-sign-vmware

# Step 6: Sign current VMware modules
log_info "Step 6: Signing current VMware modules..."
sudo /usr/local/bin/sign-vmware.sh

# Step 7: Start VMware services
log_info "Step 7: Starting VMware services..."
sudo systemctl daemon-reload
sudo systemctl enable sign-vmware.service
sudo systemctl start sign-vmware.service

# Start VMware services if they exist
sudo systemctl start vmware-usbarbitrator 2>/dev/null || true
sudo systemctl enable vmware-usbarbitrator 2>/dev/null || true
sudo systemctl start vmware-networks-server 2>/dev/null || true
sudo systemctl enable vmware-networks-server 2>/dev/null || true
sudo systemctl start vmware-networks 2>/dev/null || true
sudo systemctl enable vmware-networks 2>/dev/null || true

# Step 8: Verification
log_info "Step 8: Verifying installation..."

echo "Checking signed modules:"
for module in vmmon vmnet; do
    MODULE_PATH="/lib/modules/$(uname -r)/misc/${module}.ko"
    if [ -f "$MODULE_PATH" ]; then
        if tail -c 28 "$MODULE_PATH" | hexdump -C | grep -q "Module signature"; then
            log_info "✓ $module is signed"
        else
            log_warn "⚠ $module may not be signed"
        fi
    else
        log_warn "⚠ $module not found at $MODULE_PATH"
    fi
done

echo "Checking services:"
sudo systemctl status sign-vmware.service --no-pager -l

echo "Checking kernel hooks:"
ls -la /etc/kernel/postinst.d/99-sign-vmware

# Step 9: Load modules if not loaded
log_info "Step 9: Loading VMware modules..."
sudo modprobe -r vmmon vmnet 2>/dev/null || true
sudo modprobe vmmon
sudo modprobe vmnet

echo "Current loaded VMware modules:"
lsmod | grep vm || log_info "No VMware modules loaded (may need reboot)"

log_info "VMware Workstation installation complete!"
log_info ""
log_info "Auto-signing is configured for:"
log_info "  - VMware modules (vmmon, vmnet)"
log_info "  - Automatic signing after kernel updates"
log_info "  - Automatic signing on system boot"
log_info ""
log_info "You can manually sign modules anytime with:"
log_info "  sudo /usr/local/bin/sign-vmware.sh"
log_info ""
log_info "Start VMware Workstation from your application menu or with:"
log_info "  vmware"
log_info ""
log_warn "If modules don't load, you may need to reboot: sudo reboot"
