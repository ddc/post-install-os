#!/usr/bin/env bash
#############################################################################
set -e          # Exit on error
set -u          # Error on undefined variables
set -o pipefail # Pipe failures propagate
#############################################################################
RED="\033[1;91m"
GREEN="\033[1;92m"
YELLOW="\033[1;93m"
BLUE="\033[1;94m"
MAGENTA="\033[1;95m"
NC="\033[0m"
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
sudo dnf clean metadata -y
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
PUBLIC_DER="/etc/pki/akmods/certs/public_key.der"
PRIVATE_KEY="/etc/pki/akmods/private/private_key.pem"
CERTS_DIR="/etc/pki/akmods/certs"
PRIVATE_DIR="/etc/pki/akmods/private"
##############################################################################
log_action "=== Checking MOK enrollment status ==="
MOK_OUTPUT=$(mokutil --list-enrolled 2>/dev/null || true)
ENROLLED_AKMODS=$(echo "$MOK_OUTPUT" | grep "akmods" || true)

# Get CN of the on-disk key (if it exists)
CURRENT_KEY_CN=""
if [ -f "$PUBLIC_DER" ]; then
    CURRENT_KEY_CN=$(openssl x509 -in "$PUBLIC_DER" -inform DER -noout -subject 2>/dev/null \
        | sed 's/.*CN *= *//' || true)
fi

NEED_NEW_KEY=false
NEED_ENROLLMENT=false

if [ -n "$ENROLLED_AKMODS" ] && [ -n "$CURRENT_KEY_CN" ] \
   && echo "$MOK_OUTPUT" | grep -q "$CURRENT_KEY_CN"; then
    # Current on-disk key matches what's enrolled — everything is fine
    log_success "Current akmods signing key is enrolled in MOK"
    log_info "Enrolled key CN: $CURRENT_KEY_CN"
elif [ -n "$ENROLLED_AKMODS" ]; then
    # A stale/different akmods key is enrolled — wipe and start fresh
    log_warn "A STALE akmods key is enrolled in MOK (does not match on-disk key)"

    # Delete stale enrolled key from MOK (takes effect on reboot)
    log_action "Exporting enrolled MOK keys to find the stale akmods cert..."
    MOK_EXPORT_DIR=$(mktemp -d /tmp/mok_export_XXXXXX)
    pushd "$MOK_EXPORT_DIR" > /dev/null
    mokutil --export 2>/dev/null || true
    popd > /dev/null
    STALE_CERT=""
    for cert_file in "$MOK_EXPORT_DIR"/*; do
        [ -f "$cert_file" ] || continue
        if openssl x509 -in "$cert_file" -inform DER -noout -subject 2>/dev/null | grep -q "akmods"; then
            STALE_CERT="$cert_file"
            break
        fi
    done
    if [ -n "$STALE_CERT" ]; then
        log_action "Deleting stale akmods key from MOK (will take effect on reboot)..."
        echo ""
        log_info "You will be asked for a password to AUTHORIZE KEY DELETION."
        log_info "Use a simple password (e.g. nvidia) — same one for everything."
        echo ""
        mokutil --delete "$STALE_CERT" || log_warn "Could not schedule stale key deletion"
    else
        log_warn "Could not locate stale cert for deletion — it will remain in MOK"
    fi
    rm -rf "$MOK_EXPORT_DIR"

    # Remove stale key files AND any broken symlinks in the akmods dirs
    log_action "Cleaning up stale key files..."
    find "$CERTS_DIR" -xtype l -delete 2>/dev/null || true
    find "$PRIVATE_DIR" -xtype l -delete 2>/dev/null || true
    rm -f "$CERTS_DIR"/*.der "$PRIVATE_DIR"/*.pem "$PRIVATE_DIR"/*.priv 2>/dev/null || true

    NEED_NEW_KEY=true
    NEED_ENROLLMENT=true
else
    # No akmods key enrolled at all
    log_info "No akmods key enrolled in MOK"
    if [ ! -f "$PUBLIC_DER" ]; then
        NEED_NEW_KEY=true
    fi
    NEED_ENROLLMENT=true
fi
#############################################################################
if $NEED_NEW_KEY; then
    log_action "Generating new signing key pair..."
    kmodgenca -a
    CURRENT_KEY_CN=$(openssl x509 -in "$PUBLIC_DER" -inform DER -noout -subject 2>/dev/null \
        | sed 's/.*CN *= *//' || true)
    log_success "Signing key generated (CN: $CURRENT_KEY_CN)"
else
    log_success "Signing key on disk is valid — keeping it"
fi
#############################################################################
KVER=$(uname -r)
if $NEED_NEW_KEY; then
    log_action "Removing old kernel modules to force a signed rebuild..."
    rm -rf "/lib/modules/$KVER/extra/nvidia"
fi
log_action "Building NVIDIA kernel modules with akmods..."
sudo akmods --force
# akmods builds the RPM but may not install it if a previous version is registered.
# Force-install from cache if modules are still missing.
if [ ! -d "/lib/modules/$KVER/extra/nvidia" ]; then
    CACHED_RPM=$(find /var/cache/akmods/nvidia/ -name "kmod-nvidia-${KVER}-*.rpm" -type f 2>/dev/null | head -1)
    if [ -n "$CACHED_RPM" ]; then
        log_warn "Modules missing after akmods — force-installing from cached RPM..."
        rpm -ivh --force "$CACHED_RPM"
        depmod -a
    else
        log_error "Modules missing and no cached RPM found!"
        exit 1
    fi
fi
log_success "Kernel modules built and signed"
##############################################################################
if $NEED_ENROLLMENT; then
    log_info "Preparing MOK enrollment for the current signing key..."
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
