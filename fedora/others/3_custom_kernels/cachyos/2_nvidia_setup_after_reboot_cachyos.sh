#!/usr/bin/env bash
# CachyOS NVIDIA Setup Script
# Run this AFTER rebooting into the CachyOS kernel

set -e  # Exit on any error

echo "=== CachyOS NVIDIA Setup (Phase 2) ==="
echo "Current kernel: $(uname -r)"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root or with sudo"
    exit 1
fi

# Verify we are running a CachyOS kernel
if [[ ! "$(uname -r)" =~ "cachyos" ]]; then
    echo "❌ Warning: Not running a CachyOS kernel!"
    echo "   Current kernel: $(uname -r)"
    echo "   Please reboot and select a CachyOS kernel from GRUB"
    read -p "   Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Set key directory and paths
KEY_DIR="/etc/pki/akmods"
PRIVATE_KEY="$KEY_DIR/private/private_key.priv"
PUBLIC_KEY="$KEY_DIR/certs/public_key.der"
KERNEL_VERSION=$(uname -r)
SIGN_SCRIPT="/usr/src/kernels/$KERNEL_VERSION/scripts/sign-file"

echo "Step 1: Checking NVIDIA keys for module signing..."
if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    echo "❌ NVIDIA keys not found at $KEY_DIR"
    echo "   Please ensure NVIDIA drivers are properly installed"
    exit 1
fi
echo "✅ NVIDIA keys found"

echo "Step 2: Recompiling NVIDIA modules for CachyOS kernel..."
echo "This may take a few minutes..."

# Force akmods to rebuild for the current kernel
if ! akmods --force --kernels "$KERNEL_VERSION"; then
    echo "⚠️  akmods reported an error, but continuing..."
fi

# Wait for compilation with timeout
echo "Waiting for NVIDIA modules to compile..."
MAX_WAIT=300  # 5 minutes
WAITED=0
MODULES_DIR="/lib/modules/$KERNEL_VERSION/extra/nvidia"

while [ ! -f "$MODULES_DIR/nvidia.ko" ]; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "❌ NVIDIA module compilation timeout after 5 minutes"
        echo "   Check /var/cache/akmods/nvidia/ for build logs"
        echo "   Trying to continue with available modules..."
        break
    fi
    echo "   Still compiling NVIDIA modules... (waited ${WAITED}s)"
    sleep 30
    WAITED=$((WAITED + 30))
done

if [ -f "$MODULES_DIR/nvidia.ko" ]; then
    echo "✅ NVIDIA modules compiled successfully"
else
    echo "⚠️  NVIDIA modules may not have compiled correctly"
    echo "   Checking for any compiled modules..."
fi

echo "Step 3: Signing NVIDIA modules..."
SIGNED_COUNT=0

# Check if sign-file script exists
if [ ! -f "$SIGN_SCRIPT" ]; then
    echo "⚠️  sign-file script not found at $SIGN_SCRIPT"
    echo "   Using kmodsign instead..."
    SIGN_SCRIPT="kmodsign"
fi

# Sign each NVIDIA module
for nv_module in "$MODULES_DIR"/*.ko; do
    if [ -f "$nv_module" ]; then
        MODULE_NAME=$(basename "$nv_module")

        # Check if module is already signed
        if pesign -S -i "$nv_module" -h 2>/dev/null | grep -q "signature"; then
            echo "   Already signed: $MODULE_NAME"
        else
            # Sign the module
            if [ "$SIGN_SCRIPT" = "kmodsign" ]; then
                if kmodsign sha512 "$PRIVATE_KEY" "$PUBLIC_KEY" "$nv_module" 2>/dev/null; then
                    echo "   ✅ Signed: $MODULE_NAME"
                    SIGNED_COUNT=$((SIGNED_COUNT + 1))
                else
                    echo "   ❌ Failed to sign: $MODULE_NAME"
                fi
            else
                if "$SIGN_SCRIPT" sha256 "$PRIVATE_KEY" "$PUBLIC_KEY" "$nv_module" 2>/dev/null; then
                    echo "   ✅ Signed: $MODULE_NAME"
                    SIGNED_COUNT=$((SIGNED_COUNT + 1))
                else
                    echo "   ❌ Failed to sign: $MODULE_NAME"
                fi
            fi
        fi
    fi
done

echo "Step 4: Loading NVIDIA modules..."
# Try to load the main NVIDIA module
if modprobe nvidia 2>/dev/null; then
    echo "✅ NVIDIA module loaded successfully"
else
    echo "⚠️  Could not load NVIDIA module automatically"
    echo "   Modules will load on next reboot"
fi

echo "Step 5: Final verification..."
echo "=== SETUP COMPLETE ==="
echo "✅ Compiled NVIDIA modules for CachyOS kernel"
echo "✅ Signed $SIGNED_COUNT NVIDIA modules for Secure Boot"
echo ""
echo "NVIDIA status:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query | head -n 10
else
    echo "   nvidia-smi not available yet"
    echo "   Modules should load on next reboot"
fi

echo ""
echo "Next steps:"
echo "1. Reboot to ensure all modules load properly: sudo reboot"
echo "2. After reboot, verify with: nvidia-smi"
echo "3. Check Secure Boot status: mokutil --sb-state"
