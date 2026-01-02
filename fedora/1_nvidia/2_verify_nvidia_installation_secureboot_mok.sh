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
echo "║         NVIDIA Installation Verification                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
#############################################################################
echo ""
log_action "Checking NVIDIA GPU and Driver Status"
NVIDIA_SMI_OK=false
if command -v nvidia-smi &>/dev/null; then
    if nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu --format=csv 2>/dev/null; then
        log_success "nvidia-smi working correctly"
        NVIDIA_SMI_OK=true
    else
        log_error "nvidia-smi failed to query GPU"
    fi
else
    log_error "nvidia-smi command not found"
fi
#############################################################################
log_action "Checking Loaded Kernel Modules"
LSMOD_OUTPUT=$(lsmod)
NVIDIA_CHECK=$(echo "$LSMOD_OUTPUT" | grep nvidia || true)
if [ -n "$NVIDIA_CHECK" ]; then
    log_success "NVIDIA modules loaded:"
    echo "$NVIDIA_CHECK" | awk '{print "  - " $1 " (size: " $2 ")"}'
else
    log_error "No NVIDIA modules loaded"
    log_info "Debug: lsmod output (first 5 lines):"
    echo "$LSMOD_OUTPUT" | head -5
fi
#############################################################################
log_action "Checking Kernel Parameters"
CMDLINE=$(cat /proc/cmdline)
if echo "$CMDLINE" | grep -q "modprobe.blacklist=nouveau"; then
    log_success "Nouveau blacklisted via kernel parameter"
else
    log_warn "Nouveau not blacklisted in kernel parameters"
fi
#############################################################################
log_action "Checking Display Session Type"
if [ -n "${XDG_SESSION_TYPE:-}" ]; then
    log_info "Session type: $XDG_SESSION_TYPE"
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        log_success "Running Wayland with NVIDIA"
    fi
else
    log_warn "XDG_SESSION_TYPE not set (script run as root)"
fi

WAYLAND_COUNT=$(pgrep -c wayland 2>/dev/null || echo "0")
log_info "Wayland processes: $WAYLAND_COUNT"
#############################################################################
log_action "Checking Secure Boot Status"
if command -v mokutil &>/dev/null; then
    SB_STATUS=$(mokutil --sb-state 2>/dev/null)
    if echo "$SB_STATUS" | grep -q "SecureBoot enabled"; then
        log_info "Secure Boot: Enabled"
    else
        log_warn "Secure Boot: Disabled"
    fi
else
    # Fallback to efivars
    if [ -d /sys/firmware/efi/efivars ]; then
        SECUREBOOT_FILE=$(find /sys/firmware/efi/efivars -name 'SecureBoot-*' -type f 2>/dev/null | head -n1)
        if [ -n "$SECUREBOOT_FILE" ]; then
            SB_VALUE=$(od -An -t u1 "$SECUREBOOT_FILE" | awk '{print $(NF)}')
            if [ "$SB_VALUE" = "1" ]; then
                log_info "Secure Boot: Enabled"
            else
                log_warn "Secure Boot: Disabled"
            fi
        else
            log_warn "Secure Boot: Cannot determine status"
        fi
    else
        log_warn "Not an EFI system"
    fi
fi
#############################################################################
log_action "Checking MOK Key Enrollment"
if command -v mokutil &>/dev/null; then
    MOK_OUTPUT=$(mokutil --list-enrolled 2>/dev/null || true)
    AKMODS_CHECK=$(echo "$MOK_OUTPUT" | grep "akmods" || true)
    if [ -n "$AKMODS_CHECK" ]; then
        log_success "akmods key enrolled in MOK"
        log_info "Enrolled key details:"
        echo "$MOK_OUTPUT" | grep -B2 -A5 "akmods" | head -8
    else
        log_warn "akmods key not enrolled (Secure Boot may be disabled)"
        log_info "Debug: mokutil enrolled count: $(echo "$MOK_OUTPUT" | grep -c "key" || echo 0)"
    fi
else
    log_warn "mokutil not available"
fi
#############################################################################
log_action "Checking Module Signatures"
NVIDIA_MODULES=$(lsmod | grep nvidia | awk '{print $1}' || true)
if [ -n "$NVIDIA_MODULES" ]; then
    for module in $NVIDIA_MODULES; do
        MODINFO_OUTPUT=$(modinfo "$module" 2>/dev/null || true)
        if echo "$MODINFO_OUTPUT" | grep -q "sig_id"; then
            SIGNER=$(echo "$MODINFO_OUTPUT" | grep "signer" | head -1 | awk -F': ' '{print $2}')
            log_info "$module signed by: $SIGNER"
        else
            log_warn "$module is not signed"
        fi
    done
else
    log_warn "No NVIDIA modules to check"
fi
#############################################################################
log_action "Checking Nouveau Driver Status"
if lsmod | grep -q nouveau; then
    log_error "Nouveau is LOADED (conflicts with NVIDIA!)"
else
    log_success "Nouveau is not loaded"
fi
#############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    SUMMARY                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"

ERRORS=0

if [ "$NVIDIA_SMI_OK" = "true" ]; then
    true
else
    ERRORS=$((ERRORS + 1))
fi

if [ -n "$NVIDIA_CHECK" ]; then
    true
else
    ERRORS=$((ERRORS + 1))
fi

NOUVEAU_CHECK=$(echo "$LSMOD_OUTPUT" | grep nouveau || true)
if [ -n "$NOUVEAU_CHECK" ]; then
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    log_success "NVIDIA is FULLY WORKING!"
    log_info "Status:"
    log_info "  NVIDIA drivers loaded and functional"
    log_info "  nvidia-smi working correctly"
    if echo "$CMDLINE" | grep -q "nvidia_drm.modeset=1"; then
        log_info "  Wayland support enabled"
    fi
    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        log_info "  Working with Secure Boot enabled"
    fi
else
    log_error "Issues detected ($ERRORS problem(s))"
    log_info "Troubleshooting:"
    log_info "  1. Check dmesg for errors: dmesg | grep nvidia"
    log_info "  2. Verify module signatures: modinfo nvidia | grep sig_id"
    log_info "  3. Check Secure Boot MOK enrollment: mokutil --list-enrolled"
    log_info "  4. Rebuild initramfs: dracut --force"
fi
echo ""
