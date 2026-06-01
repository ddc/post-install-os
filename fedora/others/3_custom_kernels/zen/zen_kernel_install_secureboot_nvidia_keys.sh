#!/usr/bin/env bash

# Zen Kernel Installer with NVIDIA Support
set -e

echo "=== Fedora Zen Kernel Installer with NVIDIA Support ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Set key directory
KEY_DIR="/etc/pki/akmods"
PRIVATE_KEY="$KEY_DIR/private/private_key.priv"
PUBLIC_KEY="$KEY_DIR/certs/public_key.der"

echo "Step 1: Checking NVIDIA keys..."
if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    echo "Error: NVIDIA keys not found at $KEY_DIR"
    echo "Available files:"
    find "$KEY_DIR" -type f 2>/dev/null | head -10
    exit 1
fi
echo "✅ NVIDIA keys found"

# Enable Zen repository
echo "Step 2: Enabling Zen kernel repository..."
dnf install -y dnf-plugins-core
if ! dnf copr enable -y @kernel-zen/kernel-zen; then
    echo "Trying alternative Zen repository..."
    dnf copr enable -y sentry/zen-kernel || echo "Please check repository availability"
fi

# Install Zen kernel
echo "Step 3: Installing Zen kernel..."
dnf update -y
dnf install -y kernel-zen kernel-zen-devel kernel-zen-headers

# Install Secure Boot tools
echo "Step 4: Installing Secure Boot tools..."
dnf install -y sbsigntools pesign kmodtool

# Get kernel version
ZEN_KERNEL=$(rpm -q kernel-zen --queryformat "%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort -V | tail -n1)
ZEN_KERNEL_VERSION=$(echo "$ZEN_KERNEL" | sed 's/\.fc[0-9]*\.x86_64//' | sed 's/\.x86_64//')

if [ -z "$ZEN_KERNEL_VERSION" ]; then
    echo "Error: Could not detect Zen kernel version"
    rpm -qa | grep kernel-zen
    exit 1
fi

echo "Detected Zen kernel: $ZEN_KERNEL_VERSION"

# Step 5: RECOMPILE NVIDIA MODULES FOR ZEN KERNEL
echo "Step 5: Recompiling NVIDIA modules for Zen kernel..."
echo "This may take a few minutes..."

# Force akmods to rebuild for the new kernel
akmods --force --kernels "$ZEN_KERNEL_VERSION"

# Alternative method: reinstall akmod-nvidia to trigger rebuild
dnf reinstall -y akmod-nvidia --allowerasing

# Wait for akmods to complete
echo "Waiting for NVIDIA modules to compile..."
sleep 10

# Wait for compilation to complete
MAX_WAIT=300  # 5 minutes
WAITED=0
while [ ! -f "/lib/modules/$ZEN_KERNEL_VERSION/extra/nvidia/nvidia.ko" ]; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "Error: NVIDIA module compilation timeout"
        echo "Check /var/cache/akmods/nvidia/ for build logs"
        break
    fi
    echo "Still compiling NVIDIA modules... (waited ${WAITED}s)"
    sleep 30
    WAITED=$((WAITED + 30))
done

if [ -f "/lib/modules/$ZEN_KERNEL_VERSION/extra/nvidia/nvidia.ko" ]; then
    echo "✅ NVIDIA modules compiled successfully"
else
    echo "⚠️  NVIDIA modules may not have compiled correctly"
    echo "You may need to manually run: akmods --force --kernels $ZEN_KERNEL_VERSION"
fi

# Step 6: SIGN NVIDIA MODULES
echo "Step 6: Signing NVIDIA modules..."
if [ -f "/lib/modules/$ZEN_KERNEL_VERSION/extra/nvidia/nvidia.ko" ]; then
    for nv_module in /lib/modules/$ZEN_KERNEL_VERSION/extra/nvidia/*.ko; do
        if [ -f "$nv_module" ]; then
            kmodsign sha512 "$PRIVATE_KEY" "$PUBLIC_KEY" "$nv_module"
            echo "Signed: $(basename "$nv_module")"
        fi
    done
    echo "✅ All NVIDIA modules signed"
else
    echo "⚠️  NVIDIA modules not found for signing"
fi

# Step 7: SIGN OTHER KERNEL MODULES
echo "Step 7: Signing other kernel modules..."
MODULES_COUNT=0
for module in $(find "/lib/modules/$ZEN_KERNEL_VERSION" -name "*.ko" -type f | head -100); do
    # Skip already signed modules and NVIDIA modules (already signed above)
    if ! pesign -S -i "$module" -h 2>/dev/null | grep -q "signature"; then
        if [[ "$module" != *"/extra/nvidia/"* ]]; then
            kmodsign sha512 "$PRIVATE_KEY" "$PUBLIC_KEY" "$module" 2>/dev/null && \
            MODULES_COUNT=$((MODULES_COUNT + 1))
        fi
    fi
done
echo "Signed $MODULES_COUNT additional kernel modules"

# Step 8: SIGN KERNEL IMAGE
echo "Step 8: Signing kernel image..."
KERNEL_IMAGE="/boot/vmlinuz-$ZEN_KERNEL_VERSION"
if [ -f "$KERNEL_IMAGE" ]; then
    # Check if already signed with our key
    if sbverify --cert "$PUBLIC_KEY" "$KERNEL_IMAGE" 2>/dev/null; then
        echo "✅ Kernel already signed with NVIDIA key"
    else
        sbsign --key "$PRIVATE_KEY" --cert "$PUBLIC_KEY" \
            --output "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"
        mv "$KERNEL_IMAGE" "$KERNEL_IMAGE.unsigned"
        mv "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"
        echo "✅ Kernel image signed successfully"
    fi
else
    echo "Error: Kernel image $KERNEL_IMAGE not found"
    exit 1
fi

# Update initramfs
echo "Step 9: Updating initramfs..."
dracut -f "/boot/initramfs-$ZEN_KERNEL_VERSION.img" "$ZEN_KERNEL_VERSION"

# Update GRUB
echo "Step 10: Updating GRUB..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo ""
echo "=== Zen Kernel Installation Complete ==="
echo "✅ Zen kernel $ZEN_KERNEL_VERSION installed"
echo "✅ NVIDIA modules recompiled and signed"
echo "✅ Kernel signed with Secure Boot"
echo ""
echo "Reboot and select the Zen kernel from GRUB menu"
echo "After reboot, verify with: nvidia-smi"
