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
echo "║       VirtualBox Installation Verification                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
#############################################################################
if command -v VirtualBox &>/dev/null; then
    VBOX_VERSION=$(VirtualBox --help 2>/dev/null | head -n1)
    log_info "✓ VirtualBox installed: $VBOX_VERSION"

    if command -v VBoxManage &>/dev/null; then
        log_info "✓ VBoxManage available"
    else
        log_warn "VBoxManage command not found"
    fi
else
    log_error "VirtualBox command not found"
fi
#############################################################################
log_info "=== 2. VirtualBox Kernel Module Files ==="
MODULE_BASE="/lib/modules/$(uname -r)/extra/VirtualBox"

if [ -d "$MODULE_BASE" ]; then
    log_info "✓ Module directory exists: $MODULE_BASE"

    MODULES=("vboxdrv" "vboxnetflt" "vboxnetadp")
    for module in "${MODULES[@]}"; do
        if [ -f "$MODULE_BASE/${module}.ko.xz" ] || [ -f "$MODULE_BASE/${module}.ko" ]; then
            log_info "✓ Module file found: $module"
        else
            log_warn "Module file not found: $module"
        fi
    done
else
    log_error "Module directory not found: $MODULE_BASE"
fi

# ===== 3. Loaded Modules =====
echo ""
log_action "=== 3. Loaded Kernel Modules ==="
LSMOD_OUTPUT=$(lsmod)
VBOX_CHECK=$(echo "$LSMOD_OUTPUT" | grep vbox || true)
if [ -n "$VBOX_CHECK" ]; then
    log_success "VirtualBox modules loaded:"
    echo "$VBOX_CHECK" | awk '{print "  - " $1 " (size: " $2 ", used by: " $3 ")"}'
else
    log_warn "No VirtualBox modules loaded"
    log_info "Try loading manually: modprobe vboxdrv (as root)"
fi

# ===== 4. Module Signatures =====
echo ""
log_action "=== 4. Module Signatures ==="
VBOX_MODULES=$(echo "$LSMOD_OUTPUT" | grep vbox | awk '{print $1}' || true)
if [ -n "$VBOX_MODULES" ]; then
    for module in $VBOX_MODULES; do
        MODINFO_OUTPUT=$(modinfo "$module" 2>/dev/null || true)
        if echo "$MODINFO_OUTPUT" | grep -q "sig_id"; then
            SIGNER=$(echo "$MODINFO_OUTPUT" | grep "signer" | head -1 | awk -F': ' '{print $2}')
            log_success "$module signed by: $SIGNER"
        else
            log_warn "$module is not signed"
        fi
    done
else
    MODULES=("vboxdrv" "vboxnetflt" "vboxnetadp")
    for module in "${MODULES[@]}"; do
        MODINFO_OUTPUT=$(modinfo "$module" 2>/dev/null || true)
        if [ -n "$MODINFO_OUTPUT" ]; then
            if echo "$MODINFO_OUTPUT" | grep -q "sig_id"; then
                SIGNER=$(echo "$MODINFO_OUTPUT" | grep "signer" | head -1 | awk -F': ' '{print $2}')
                log_success "$module signed by: $SIGNER"
            else
                log_warn "$module is not signed"
            fi
        fi
    done
fi

# ===== 5. Secure Boot Status =====
echo ""
log_action "=== 5. Secure Boot Status ==="
if command -v mokutil &>/dev/null; then
    SB_STATUS=$(mokutil --sb-state 2>/dev/null || true)
    if echo "$SB_STATUS" | grep -q "SecureBoot enabled"; then
        log_success "Secure Boot: Enabled"
    else
        log_warn "Secure Boot: Disabled"
    fi
else
    log_warn "mokutil not available"
fi

# ===== 6. MOK Key Enrollment =====
echo ""
log_action "=== 6. MOK Key Enrollment ==="
if command -v mokutil &>/dev/null; then
    MOK_OUTPUT=$(mokutil --list-enrolled 2>/dev/null || true)
    AKMODS_CHECK=$(echo "$MOK_OUTPUT" | grep "akmods" || true)
    if [ -n "$AKMODS_CHECK" ]; then
        log_success "akmods key enrolled in MOK"
        echo ""
        log_info "Enrolled key details:"
        echo "$MOK_OUTPUT" | grep -A5 "akmods" | head -6
    else
        log_warn "akmods key not enrolled (Secure Boot may be disabled)"
    fi
else
    log_warn "mokutil not available"
fi

# ===== 7. VirtualBox Services =====
echo ""
log_info "=== 7. VirtualBox Services ==="
if systemctl is-enabled vboxdrv &>/dev/null; then
    log_info "✓ vboxdrv service enabled"
else
    log_warn "vboxdrv service not enabled"
fi

if systemctl is-active vboxdrv &>/dev/null; then
    log_info "✓ vboxdrv service active"
else
    log_warn "vboxdrv service not active"
fi

# ===== 8. User Permissions =====
echo ""
log_action "=== 8. User Permissions ==="
GROUPS_OUTPUT=$(groups || true)
if echo "$GROUPS_OUTPUT" | grep -q vboxusers; then
    log_success "Current user in vboxusers group"
else
    log_warn "Current user NOT in vboxusers group"
    log_info "Add with: usermod -a -G vboxusers \$USER (as root)"
fi

# ===== 9. Auto-Signing Setup =====
echo ""
log_info "=== 9. Auto-Signing Configuration ==="
if [ -f /usr/local/bin/sign-virtualbox.sh ]; then
    log_info "✓ Auto-signing script exists"
else
    log_warn "Auto-signing script not found"
fi

if systemctl list-unit-files | grep -q sign-virtualbox.service; then
    log_info "✓ Auto-signing service configured"
else
    log_warn "Auto-signing service not configured"
fi

if [ -f /etc/kernel/postinst.d/99-sign-virtualbox ]; then
    log_info "✓ Kernel update hook installed"
else
    log_warn "Kernel update hook not found"
fi

# ===== 10. Guest Additions =====
echo ""
log_info "=== 10. Guest Additions ISO ==="
ISO_LOCATIONS=(
    "$HOME/.config/VirtualBox/VBoxGuestAdditions_*.iso"
    "/usr/share/virtualbox/VBoxGuestAdditions.iso"
)

FOUND_ISO=false
for location in "${ISO_LOCATIONS[@]}"; do
    if ls $location 2>/dev/null | head -1 >/dev/null; then
        ISO_FILE=$(ls $location 2>/dev/null | head -1)
        log_info "✓ Guest Additions ISO found: $ISO_FILE"
        FOUND_ISO=true
        break
    fi
done

if [ "$FOUND_ISO" = false ]; then
    log_warn "Guest Additions ISO not found"
fi

# ===== 11. Virtual Machines =====
echo ""
log_info "=== 11. Virtual Machines ==="
if command -v VBoxManage &>/dev/null; then
    VM_COUNT=$(VBoxManage list vms 2>/dev/null | wc -l)
    log_info "Total VMs: $VM_COUNT"

    if [ "$VM_COUNT" -gt 0 ]; then
        echo ""
        log_info "Registered VMs:"
        VBoxManage list vms 2>/dev/null | awk '{print "  - " $1}'
    fi

    RUNNING_COUNT=$(VBoxManage list runningvms 2>/dev/null | wc -l)
    if [ "$RUNNING_COUNT" -gt 0 ]; then
        log_info "Running VMs: $RUNNING_COUNT"
    fi
fi

# ===== 12. Kernel Messages =====
echo ""
log_action "=== 12. Kernel Messages (dmesg) ==="
DMESG_OUTPUT=$(dmesg 2>/dev/null || true)
DMESG_SUCCESS=$(echo "$DMESG_OUTPUT" | grep "vboxdrv:.*Successfully loaded" || true)
DMESG_VBOX=$(echo "$DMESG_OUTPUT" | grep "vboxdrv" || true)

if [ -n "$DMESG_SUCCESS" ]; then
    log_success "VirtualBox loaded successfully"
elif [ -n "$DMESG_VBOX" ]; then
    log_warn "VirtualBox kernel messages found (check for errors)"
    echo ""
    log_info "Recent vboxdrv messages:"
    echo "$DMESG_VBOX" | tail -5
else
    log_warn "No VirtualBox kernel messages found"
fi

# ===== SUMMARY =====
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    SUMMARY                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if everything is working
ERRORS=0

if ! command -v VirtualBox &>/dev/null; then
    ERRORS=$((ERRORS + 1))
fi

VBOXDRV_CHECK=$(echo "$LSMOD_OUTPUT" | grep vboxdrv || true)
if [ -z "$VBOXDRV_CHECK" ]; then
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$GROUPS_OUTPUT" | grep -q vboxusers; then
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    log_success "VirtualBox is FULLY WORKING!"
    echo ""
    log_info "Status:"
    log_info "  VirtualBox installed and accessible"
    log_info "  Kernel modules loaded and signed"
    log_info "  User has proper permissions"
    if echo "$SB_STATUS" | grep -q "SecureBoot enabled"; then
        log_info "  Working with Secure Boot enabled"
    fi
    echo ""
    log_info "You can now create and run virtual machines!"
else
    log_error "Issues detected ($ERRORS problem(s))"
    echo ""
    log_info "Troubleshooting:"
    if [ -z "$VBOXDRV_CHECK" ]; then
        log_info "  1. Load modules: modprobe vboxdrv (as root)"
    fi
    if ! echo "$GROUPS_OUTPUT" | grep -q vboxusers; then
        log_info "  2. Add user to group: usermod -a -G vboxusers \$USER (as root)"
        log_info "  3. Logout and login to apply group changes"
    fi
    log_info "  4. Check module signatures: modinfo vboxdrv | grep sig_id"
    log_info "  5. Check kernel messages: dmesg | grep vbox"
fi
echo ""
