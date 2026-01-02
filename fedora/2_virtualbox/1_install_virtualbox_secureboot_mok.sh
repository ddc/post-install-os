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
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║   VirtualBox Installation with Secure Boot (Using Shared akmods Keys)    ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
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
log_action "Searching for akmods signing keys..."
CERT_DIR="/etc/pki/akmods/certs"
PRIVATE_DIR="/etc/pki/akmods/private"
if [ ! -d "$CERT_DIR" ]; then
    log_error "akmods certificate directory not found: $CERT_DIR"
    log_error "Please run the NVIDIA installation script first to generate keys"
    log_error "Or run: kmodgenca -a"
    exit 1
fi
PUBLIC_DER=$(find "$CERT_DIR" -name "fedora_*.der" -type f 2>/dev/null | head -n1)
if [ -z "$PUBLIC_DER" ] || [ ! -f "$PUBLIC_DER" ]; then
    log_error "No fedora_*.der key found in $CERT_DIR"
    log_error "Please run the NVIDIA installation script first to generate keys"
    log_error "Or run: kmodgenca -a"
    exit 1
fi
CERT_BASENAME=$(basename "$PUBLIC_DER" .der)
PRIVATE_KEY="$PRIVATE_DIR/${CERT_BASENAME}.priv"
if [ ! -f "$PRIVATE_KEY" ]; then
    log_error "Private key not found: $PRIVATE_KEY"
    log_error "Expected to find private key matching: $CERT_BASENAME"
    exit 1
fi
PUBLIC_CERT="$CERT_DIR/${CERT_BASENAME}.pem"
if [ ! -f "$PUBLIC_CERT" ]; then
    log_action "Converting DER to PEM format for signing..."
    openssl x509 -in "$PUBLIC_DER" -inform DER -out "$PUBLIC_CERT" -outform PEM
    log_success "Created PEM certificate: $PUBLIC_CERT"
fi

log_success "Found akmods signing keys:"
log_info "  Key name: $CERT_BASENAME"
log_info "  Private: $PRIVATE_KEY"
log_info "  Certificate (PEM): $PUBLIC_CERT"
log_info "  Certificate (DER): $PUBLIC_DER"
#############################################################################
log_action "Checking MOK enrollment status"
MOK_OUTPUT=$(mokutil --list-enrolled 2>/dev/null || true)
AKMODS_CHECK=$(echo "$MOK_OUTPUT" | grep "akmods" || true)
if [ -n "$AKMODS_CHECK" ]; then
    log_success "akmods key is already enrolled in MOK"
    log_info "Skipping MOK enrollment (key is ready to use)"
    log_info "Enrolled key details:"
    echo "$MOK_OUTPUT" | grep -A3 "akmods" | head -4
else
    log_info "akmods key is not yet enrolled - preparing MOK enrollment"
    echo ""
    log_info "╔══════════════════════════════════════════════════════════════╗"
    log_info "║                  IMPORTANT: MOK PASSWORD                     ║"
    log_info "╠══════════════════════════════════════════════════════════════╣"
    log_info "║ You will now set a password for Secure Boot key enrollment.  ║"
    log_info "║                                                              ║"
    log_info "║ Choose a SIMPLE password you'll remember:                    ║"
    log_info "║   • Example: virtualbox                                      ║"
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

        MOK_ENROLLMENT_PENDING=true
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
#############################################################################
log_action "Setting up RPM Fusion repositories"
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    log_action "Installing RPM Fusion FREE repository..."
    dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    log_success "RPM Fusion FREE installed"
else
    log_success "RPM Fusion FREE already installed"
fi

if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    log_action "Installing RPM Fusion NONFREE repository..."
    dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    log_success "RPM Fusion NONFREE installed"
else
    log_success "RPM Fusion NONFREE already installed"
fi
#############################################################################
log_action "Installing VirtualBox and dependencies"
dnf install -y \
    virtualbox \
    virtualbox-guest-additions \
    kernel-devel \
    kernel-headers \
    akmods \
    elfutils-libelf-devel

log_success "VirtualBox packages installed"
#############################################################################
log_action "Building VirtualBox kernel modules"
akmods --force
log_info "Waiting for module build..."
sleep 10

VBOX_MODULE_DIR="/lib/modules/$(uname -r)/extra/VirtualBox"
if [ -d "$VBOX_MODULE_DIR" ]; then
    MODULES_FOUND=$(find "$VBOX_MODULE_DIR" -name "*.ko*" 2>/dev/null | wc -l)
    if [ "$MODULES_FOUND" -gt 0 ]; then
        log_success "Found $MODULES_FOUND VirtualBox modules"
        find "$VBOX_MODULE_DIR" -name "*.ko*" -print0 2>/dev/null | xargs -0 -n1 basename
    else
        log_error "No VirtualBox modules found!"
        exit 1
    fi
else
    log_error "VirtualBox module directory not found!"
    exit 1
fi
#############################################################################
log_action "Setting up user permissions"
usermod -a -G vboxusers "$USER"
log_success "Added $USER to vboxusers group"
#############################################################################
log_action "Fixing VirtualBox device permissions (udev rules)"
tee /etc/udev/rules.d/60-vboxdrv.rules > /dev/null << 'EOF'
# VirtualBox device permissions - Allow vboxusers group access
KERNEL=="vboxdrv", OWNER="root", GROUP="vboxusers", MODE="0660"
KERNEL=="vboxdrvu", OWNER="root", GROUP="root", MODE="0666"
KERNEL=="vboxnetctl", OWNER="root", GROUP="vboxusers", MODE="0660"
SUBSYSTEM=="usb_device", ACTION=="add", RUN+="/usr/lib/udev/VBoxCreateUSBNode.sh $major $minor $attr{bDeviceClass} vboxusers"
SUBSYSTEM=="usb", ACTION=="add", ENV{DEVTYPE}=="usb_device", RUN+="/usr/lib/udev/VBoxCreateUSBNode.sh $major $minor $attr{bDeviceClass} vboxusers"
SUBSYSTEM=="usb_device", ACTION=="remove", RUN+="/usr/lib/udev/VBoxCreateUSBNode.sh --remove $major $minor"
SUBSYSTEM=="usb", ACTION=="remove", ENV{DEVTYPE}=="usb_device", RUN+="/usr/lib/udev/VBoxCreateUSBNode.sh --remove $major $minor"
EOF
udevadm control --reload-rules
udevadm trigger
log_success "Fixed VirtualBox udev rules for vboxusers group access"
#############################################################################
log_action "Signing VirtualBox modules"
SIGN_TOOL=""
for tool_path in \
    /usr/src/kernels/$(uname -r)/scripts/sign-file \
    /usr/lib/modules/$(uname -r)/build/scripts/sign-file \
    $(which sign-file 2>/dev/null); do
    if [ -f "$tool_path" ] && [ -x "$tool_path" ]; then
        SIGN_TOOL="$tool_path"
        break
    fi
done

if [ -z "$SIGN_TOOL" ]; then
    log_warn "sign-file tool not found!"
    log_action "Installing kernel-devel for current kernel..."
    KERNEL_VERSION="$(uname -r)"
    dnf install -y "kernel-devel-${KERNEL_VERSION}"

    SIGN_TOOL="/usr/src/kernels/${KERNEL_VERSION}/scripts/sign-file"
    if [ ! -f "$SIGN_TOOL" ]; then
        log_error "Still cannot find sign-file tool"
        exit 1
    fi
fi

log_success "Using signing tool: $SIGN_TOOL"
MODULES=("vboxdrv" "vboxnetflt" "vboxnetadp")
SIGNED_COUNT=0

for module in "${MODULES[@]}"; do
    MODULE_PATH_XZ="$VBOX_MODULE_DIR/${module}.ko.xz"
    MODULE_PATH_KO="$VBOX_MODULE_DIR/${module}.ko"

    if [ -f "$MODULE_PATH_XZ" ]; then
        log_action "Signing compressed module: $module"

        # Decompress and sign (keep uncompressed for compatibility)
        TEMP_DIR=$(mktemp -d)
        xz -d -c "$MODULE_PATH_XZ" > "$TEMP_DIR/${module}.ko"

        if "$SIGN_TOOL" sha512 "$PRIVATE_KEY" "$PUBLIC_CERT" "$TEMP_DIR/${module}.ko"; then
            # Remove compressed version and use uncompressed signed module
            rm -f "$MODULE_PATH_XZ"
            mv "$TEMP_DIR/${module}.ko" "$MODULE_PATH_KO"
            chmod 644 "$MODULE_PATH_KO"
            # Restore correct SELinux context
            restorecon "$MODULE_PATH_KO" 2>/dev/null || true
            log_success "Signed: $module (uncompressed)"
            SIGNED_COUNT=$((SIGNED_COUNT + 1))
        else
            log_warn "Failed to sign: $module"
        fi

        rm -rf "$TEMP_DIR"

    elif [ -f "$MODULE_PATH_KO" ]; then
        log_action "Signing uncompressed module: $module"

        if "$SIGN_TOOL" sha512 "$PRIVATE_KEY" "$PUBLIC_CERT" "$MODULE_PATH_KO"; then
            log_success "Signed: $module"
            SIGNED_COUNT=$((SIGNED_COUNT + 1))
        else
            log_warn "Failed to sign: $module"
        fi
    else
        log_warn "Module not found: $module"
    fi
done
log_success "Signed $SIGNED_COUNT of ${#MODULES[@]} modules"
#############################################################################
log_action "Creating auto-signing script"
tee /usr/local/bin/sign-virtualbox.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
# Auto-sign VirtualBox modules after kernel updates

# Dynamically find akmods keys (fedora_*)
CERT_DIR="/etc/pki/akmods/certs"
PRIVATE_DIR="/etc/pki/akmods/private"

# Find the actual fedora_*.der file
PUBLIC_DER=$(find "$CERT_DIR" -name "fedora_*.der" -type f 2>/dev/null | head -n1)
if [ -z "$PUBLIC_DER" ]; then
    echo "Error: No akmods key found in $CERT_DIR"
    exit 1
fi

CERT_BASENAME=$(basename "$PUBLIC_DER" .der)
PRIVATE_KEY="$PRIVATE_DIR/${CERT_BASENAME}.priv"
PUBLIC_CERT="$CERT_DIR/${CERT_BASENAME}.pem"

# Create PEM if doesn't exist
if [ ! -f "$PUBLIC_CERT" ]; then
    openssl x509 -in "$PUBLIC_DER" -inform DER -out "$PUBLIC_CERT" -outform PEM
fi

MODULES=("vboxdrv" "vboxnetflt" "vboxnetadp")
VBOX_MODULE_DIR="/lib/modules/$(uname -r)/extra/VirtualBox"

# Find sign-file tool
SIGN_TOOL=""
for path in /usr/src/kernels/$(uname -r)/scripts/sign-file /usr/lib/modules/$(uname -r)/build/scripts/sign-file; do
    if [ -f "$path" ] && [ -x "$path" ]; then
        SIGN_TOOL="$path"
        break
    fi
done

if [ -z "$SIGN_TOOL" ]; then
    echo "Error: sign-file tool not found"
    exit 1
fi

echo "Signing VirtualBox modules for kernel $(uname -r)..."
echo "Using key: $CERT_BASENAME"

for module in "${MODULES[@]}"; do
    MODULE_PATH_XZ="$VBOX_MODULE_DIR/${module}.ko.xz"
    MODULE_PATH_KO="$VBOX_MODULE_DIR/${module}.ko"

    if [ -f "$MODULE_PATH_XZ" ]; then
        echo "Signing compressed: $module"
        TEMP_DIR=$(mktemp -d)
        xz -d -c "$MODULE_PATH_XZ" > "$TEMP_DIR/${module}.ko"
        "$SIGN_TOOL" sha512 "$PRIVATE_KEY" "$PUBLIC_CERT" "$TEMP_DIR/${module}.ko"
        # Keep uncompressed for compatibility
        rm -f "$MODULE_PATH_XZ"
        mv "$TEMP_DIR/${module}.ko" "$MODULE_PATH_KO"
        chmod 644 "$MODULE_PATH_KO"
        # Restore correct SELinux context
        restorecon "$MODULE_PATH_KO" 2>/dev/null || true
        rm -rf "$TEMP_DIR"
        echo "✓ Signed: $module (uncompressed)"
    elif [ -f "$MODULE_PATH_KO" ]; then
        echo "Signing uncompressed: $module"
        "$SIGN_TOOL" sha512 "$PRIVATE_KEY" "$PUBLIC_CERT" "$MODULE_PATH_KO"
        echo "✓ Signed: $module"
    fi
done

depmod -a
echo "VirtualBox modules signed successfully"
EOF
chmod +x /usr/local/bin/sign-virtualbox.sh
log_success "Created: /usr/local/bin/sign-virtualbox.sh"
#############################################################################
log_action "Creating systemd service for auto-signing..."
tee /etc/systemd/system/sign-virtualbox.service > /dev/null << 'EOF'
[Unit]
Description=Sign VirtualBox kernel modules for Secure Boot
After=akmods.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sign-virtualbox.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sign-virtualbox.service
log_success "Systemd service enabled"
#############################################################################
log_action "Creating kernel update hook..."
mkdir -p /etc/kernel/postinst.d
tee /etc/kernel/postinst.d/99-sign-virtualbox > /dev/null << 'EOF'
#!/usr/bin/env bash
/usr/local/bin/sign-virtualbox.sh
EOF
chmod +x /etc/kernel/postinst.d/99-sign-virtualbox
log_success "Kernel hook created"
#############################################################################
log_action "Updating module dependencies..."
depmod -a
log_success "Module dependencies updated"
#############################################################################
log_action "Starting VirtualBox services"
if systemctl enable vboxdrv 2>/dev/null; then
    log_success "Enabled vboxdrv service"
fi
if systemctl start vboxdrv 2>/dev/null; then
    log_success "Started vboxdrv service"
else
    log_warn "Could not start vboxdrv service (may need reboot)"
fi
#############################################################################
log_action "Loading VirtualBox modules..."
for module in vboxdrv vboxnetflt vboxnetadp; do
    if modprobe "$module" 2>/dev/null; then
        log_success "Loaded: $module"
    else
        log_warn "Could not load: $module (may need reboot)"
    fi
done
#############################################################################
log_action "Downloading VirtualBox Guest Additions ISO"
VBOX_VERSION=$(rpm -q --queryformat '%{VERSION}' VirtualBox 2>/dev/null || echo "")
if [ -z "$VBOX_VERSION" ]; then
    log_warn "Could not detect VirtualBox version from RPM"
    log_info "Skipping Guest Additions ISO download"
    log_info "You can download it manually from: https://www.virtualbox.org/wiki/Downloads"
else
    ISO_DIR="$HOME/.config/VirtualBox"
    mkdir -p "$ISO_DIR"

    log_info "VirtualBox version: $VBOX_VERSION"
    log_action "Downloading Guest Additions ISO..."

    if wget -q --show-progress -O "$ISO_DIR/VBoxGuestAdditions_$VBOX_VERSION.iso" \
        "https://download.virtualbox.org/virtualbox/$VBOX_VERSION/VBoxGuestAdditions_$VBOX_VERSION.iso" 2>/dev/null; then
        log_success "Guest Additions ISO downloaded to: $ISO_DIR/VBoxGuestAdditions_$VBOX_VERSION.iso"
    else
        log_warn "Failed to download Guest Additions ISO for version $VBOX_VERSION"
        log_info "You can download it manually from: https://www.virtualbox.org/wiki/Downloads"
    fi
fi
#############################################################################
log_action "Verification"

# Check VirtualBox installation
if command -v VirtualBox &>/dev/null; then
    log_success "VirtualBox installed: $(VirtualBox --help 2>/dev/null | head -n1)"
else
    log_error "VirtualBox command not found"
fi

# Check loaded modules
LSMOD_OUTPUT=$(lsmod)
VBOX_CHECK=$(echo "$LSMOD_OUTPUT" | grep vbox || true)
if [ -n "$VBOX_CHECK" ]; then
    log_success "VirtualBox modules loaded:"
    echo "$VBOX_CHECK" | awk '{print "  - " $1}'
else
    log_warn "VirtualBox modules not loaded (may need reboot or group re-login)"
fi

# Check module signatures
log_action "Checking module signatures:"
for module in vboxdrv vboxnetflt vboxnetadp; do
    MODINFO_OUTPUT=$(modinfo "$module" 2>/dev/null || true)
    if echo "$MODINFO_OUTPUT" | grep -q "sig_id"; then
        SIGNER=$(echo "$MODINFO_OUTPUT" | grep "signer" | head -1 | awk -F': ' '{print $2}')
        log_success "$module signed by: $SIGNER"
    else
        log_warn "$module signature not verified"
    fi
done

# Check user groups
GROUPS_OUTPUT=$(groups || true)
if echo "$GROUPS_OUTPUT" | grep -q vboxusers; then
    log_success "Current session has vboxusers group"
else
    log_warn "vboxusers group not active (logout/login required)"
fi
#############################################################################
log_success "INSTALLATION COMPLETE"
echo ""
log_success "VirtualBox installed with Secure Boot support (using shared akmods keys)"
echo ""
log_info "What was configured:"
log_success "VirtualBox and dependencies installed"
log_success "Kernel modules built and signed with shared akmods keys"
log_success "Auto-signing configured for kernel updates"
log_success "User added to vboxusers group"
log_success "Guest Additions ISO downloaded"
echo ""

if [ "${MOK_ENROLLMENT_PENDING:-false}" = "true" ]; then
    log_info "NEXT STEPS:"
    echo "  1. sudo reboot"
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
    log_info "AFTER MOK ENROLLMENT:"
    echo "   - LOGOUT AND LOGIN (to activate vboxusers group)"
    echo "   - Launch VirtualBox: VirtualBox"
    echo ""
else
    log_info "NEXT STEPS:"
    echo "  1. LOGOUT AND LOGIN (to activate vboxusers group)"
    echo "  2. Launch VirtualBox: VirtualBox"
    echo ""
fi

log_info "NOTES:"
echo "   - VirtualBox uses the same shared akmods key"
if [ "${MOK_ENROLLMENT_PENDING:-false}" = "true" ]; then
    echo "   - MOK enrollment scheduled for next reboot"
else
    echo "   - MOK key already enrolled (shared with NVIDIA and other kernel modules)"
fi
echo "   - After kernel updates, modules will be auto-signed"
echo "   - Manual signing: /usr/local/bin/sign-virtualbox.sh (as root)"
echo ""

FINAL_LSMOD=$(lsmod)
FINAL_VBOX_CHECK=$(echo "$FINAL_LSMOD" | grep vbox || true)
if [ -z "$FINAL_VBOX_CHECK" ]; then
    log_warn "TROUBLESHOOTING:"
    echo "  If modules don't load after reboot:"
    echo "  1. Check signatures: modinfo vboxdrv | grep sig_id"
    echo "  2. Re-sign modules: /usr/local/bin/sign-virtualbox.sh (as root)"
    echo "  3. Load manually: modprobe vboxdrv (as root)"
fi
