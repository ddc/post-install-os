#!/usr/bin/env bash

# Xanmod Kernel Installer with NVIDIA Support
set -e

echo "=== Fedora Xanmod Kernel Installer with NVIDIA Support ==="

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
    exit 1
fi
echo "✅ NVIDIA keys found"

# Enable Xanmod repository
echo "Step 2: Enabling Xanmod repository..."
dnf install -y dnf-plugins-core

# Add Xanmod repository
cat > /etc/yum.repos.d/xanmod.repo << 'EOF'
[xanmod]
name=Xanmod Kernel
baseurl=https://dl.xanmod.org/releases/rpm/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://dl.xanmod.org/releases/static/xanmod-pub.gpg
EOF

# Update and install Xanmod kernel
echo "Step 3: Installing Xanmod kernel..."
dnf update -y

# Show available Xanmod versions
echo "Available Xanmod versions:"
dnf search xanmod 2>/dev/null | grep -E '^linux-xanmod' || echo "Trying direct installation..."

# Install Xanmod LTS (most stable)
if dnf install -y linux-xanmod-lts linux-xanmod-lts-headers; then
    echo "✅ Installed Xanmod LTS"
else
    # Try regular version
    echo "Trying regular Xanmod version..."
    dnf install -y linux-xanmod linux-xanmod-headers || {
        echo "Error: Could not install Xanmod kernel"
        exit 1
    }
fi

# Install Secure Boot tools
echo "Step 4: Installing Secure Boot tools..."
dnf install -y sbsigntools pesign kmodtool

# Get kernel version
XANMOD_KERNEL=$(rpm -qa | grep -E '^linux-xanmod' | grep -v headers | head -1)
if [ -z "$XANMOD_KERNEL" ]; then
    echo "Error: Could not find installed Xanmod kernel"
    rpm -qa | grep xanmod
    exit 1
fi

XANMOD_KERNEL_VERSION=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$XANMOD_KERNEL" | sed 's/\.x86_64//')
echo "Detected Xanmod kernel: $XANMOD_KERNEL_VERSION"

# Step 5: RECOMPILE NVIDIA MODULES FOR XANMOD KERNEL
echo "Step 5: Recompiling NVIDIA modules for Xanmod kernel..."
echo "This may take a few minutes..."

# Force akmods to rebuild for the new kernel
akmods --force --kernels "$XANMOD_KERNEL_VERSION"

# Alternative method: reinstall akmod-nvidia to trigger rebuild
dnf reinstall -y akmod-nvidia --allowerasing

# Wait for akmods to complete
echo "Waiting for NVIDIA modules to compile..."
sleep 10

# Wait for compilation to complete
MAX_WAIT=300  # 5 minutes
WAITED=0
while [ ! -f "/lib/modules/$XANMOD_KERNEL_VERSION/extra/nvidia/nvidia.ko" ]; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "Error: NVIDIA module compilation timeout"
        echo "Check /var/cache/akmods/nvidia/ for build logs"
        break
    fi
    echo "Still compiling NVIDIA modules... (waited ${WAITED}s)"
    sleep 30
    WAITED=$((WAITED + 30))
done

if [ -f "/lib/modules/$XANMOD_KERNEL_VERSION/extra/nvidia/nvidia.ko" ]; then
    echo "✅ NVIDIA modules compiled successfully"
else
    echo "⚠️  NVIDIA modules may not have compiled correctly"
    echo "You may need to manually run: akmods --force --kernels $XANMOD_KERNEL_VERSION"
fi

# Step 6: SIGN NVIDIA MODULES
echo "Step 6: Signing NVIDIA modules..."
if [ -f "/lib/modules/$XANMOD_KERNEL_VERSION/extra/nvidia/nvidia.ko" ]; then
    for nv_module in /lib/modules/$XANMOD_KERNEL_VERSION/extra/nvidia/*.ko; do
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
for module in $(find "/lib/modules/$XANMOD_KERNEL_VERSION" -name "*.ko" -type f | head -100); do
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
KERNEL_IMAGE="/boot/vmlinuz-$XANMOD_KERNEL_VERSION"
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
    # Try alternative naming
    ALT_KERNEL_IMAGE="/boot/vmlinuz-$XANMOD_KERNEL_VERSION.x86_64"
    if [ -f "$ALT_KERNEL_IMAGE" ]; then
        echo "Found kernel at alternative location: $ALT_KERNEL_IMAGE"
        KERNEL_IMAGE="$ALT_KERNEL_IMAGE"
        sbsign --key "$PRIVATE_KEY" --cert "$PUBLIC_KEY" \
            --output "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"
        mv "$KERNEL_IMAGE" "$KERNEL_IMAGE.unsigned"
        mv "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"
    else
        exit 1
    fi
fi

# Update initramfs
echo "Step 9: Updating initramfs..."
dracut -f "/boot/initramfs-$XANMOD_KERNEL_VERSION.img" "$XANMOD_KERNEL_VERSION"

# Update GRUB
echo "Step 10: Updating GRUB..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo ""
echo "=== Xanmod Kernel Installation Complete ==="
echo "✅ Xanmod kernel $XANMOD_KERNEL_VERSION installed"
echo "✅ NVIDIA modules recompiled and signed"
echo "✅ Kernel signed with Secure Boot"
echo ""
echo "Reboot and select the Xanmod kernel from GRUB menu"
echo "After reboot, verify with: nvidia-smi"
