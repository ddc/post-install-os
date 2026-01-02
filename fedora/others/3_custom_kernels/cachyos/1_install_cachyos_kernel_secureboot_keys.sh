#!/usr/bin/env bash
# CachyOS Kernel Installer for Fedora with NVIDIA Support
# https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos

set -e

echo "=== Fedora CachyOS Kernel Installer with NVIDIA Support ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Create kernel signing keys directory
KERNEL_KEY_DIR="/root/kernel_keys"
mkdir -p "$KERNEL_KEY_DIR"

# Generate proper kernel signing keys
echo "Step 1: Generating proper kernel signing keys..."
cd "$KERNEL_KEY_DIR"

# Generate proper X.509 certificate with all required fields
cat > kernel_cert.conf << 'EOF'
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
CN = Kernel Signing Key
O = Secure Boot
C = US

[ v3_ca ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

echo "Generating new kernel signing keys with proper X.509 format..."
# Generate private key and certificate in one step
openssl req -new -x509 -newkey rsa:2048 \
    -keyout kernel_key.priv \
    -out kernel_key.pem \
    -days 3650 \
    -config kernel_cert.conf \
    -nodes

# Convert to DER format for MOK
openssl x509 -in kernel_key.pem -outform DER -out kernel_key.der

# Clean up
rm -f kernel_cert.conf

chmod 600 kernel_key.priv
echo "✅ New kernel signing keys generated in $KERNEL_KEY_DIR"

# Verify the certificates
echo "Verifying certificate formats..."
if openssl x509 -in kernel_key.pem -text -noout >/dev/null 2>&1; then
    echo "✅ PEM certificate is valid"
else
    echo "❌ PEM certificate verification failed"
    exit 1
fi

if openssl x509 -in kernel_key.der -inform der -text -noout >/dev/null 2>&1; then
    echo "✅ DER certificate is valid"
else
    echo "❌ DER certificate verification failed"
    exit 1
fi

KERNEL_PRIVATE_KEY="$KERNEL_KEY_DIR/kernel_key.priv"
KERNEL_PUBLIC_PEM="$KERNEL_KEY_DIR/kernel_key.pem"
KERNEL_PUBLIC_DER="$KERNEL_KEY_DIR/kernel_key.der"

# Set NVIDIA key directory for module signing
NVIDIA_KEY_DIR="/etc/pki/akmods"
NVIDIA_PRIVATE_KEY="$NVIDIA_KEY_DIR/private/private_key.priv"
NVIDIA_PUBLIC_KEY="$NVIDIA_KEY_DIR/certs/public_key.der"

echo "Step 2: Checking NVIDIA keys for module signing..."
if [ ! -f "$NVIDIA_PRIVATE_KEY" ] || [ ! -f "$NVIDIA_PUBLIC_KEY" ]; then
    echo "⚠️  NVIDIA keys not found - module signing may fail"
else
    echo "✅ NVIDIA keys found for module signing"
fi

# Clean up any existing incorrect repository files first
echo "Step 3: Cleaning up any existing repository configurations..."
rm -f /etc/yum.repos.d/*cachyos* 2>/dev/null || true

# Enable CachyOS COPR repository
echo "Step 4: Enabling CachyOS COPR repository..."
dnf install -y dnf-plugins-core

# Enable the working COPR repository
if dnf copr enable -y bieszczaders/kernel-cachyos; then
    echo "✅ Successfully enabled bieszczaders/kernel-cachyos COPR repository"
else
    echo "Error: Could not enable bieszczaders/kernel-cachyos COPR repository"
    exit 1
fi

# Install CachyOS kernel
echo "Step 5: Installing CachyOS kernel..."
dnf update -y

# Install CachyOS kernel with development packages
echo "Installing kernel-cachyos with development packages..."
dnf install -y kernel-cachyos kernel-cachyos-devel-matched
# OR for realtime kernel
# sudo dnf install kernel-cachyos-rt kernel-cachyos-rt-devel-matched

# COPR repository hosting addon packages
echo "Step 6: Enabling the COPR repository hosting addon packages..."
dnf copr enable -y bieszczaders/kernel-cachyos-addons
dnf swap -y zram-generator-defaults cachyos-settings
# Apply All Sysctl Settings
sudo sysctl --system
# Enable PCI Latency Optimization (Recommended for gaming/performance)
sudo systemctl enable --now pci-latency.service

# If you are using SElinux. Enable the policy to load kernel modules
echo "Step 7: Enabling the policy to load kernel modules..."
setsebool -P domain_kernel_load_modules on

# Install Secure Boot tools
echo "Step 8: Installing Secure Boot tools..."
dnf install -y sbsigntools pesign kmodtool

# Get kernel version
CACHYOS_KERNEL=$(rpm -qa | grep 'kernel-cachyos' | grep -v headers | head -1)
if [ -z "$CACHYOS_KERNEL" ]; then
    echo "Error: Could not find installed CachyOS kernel package"
    exit 1
fi

CACHYOS_KERNEL_VERSION=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$CACHYOS_KERNEL")
echo "Detected CachyOS kernel: $CACHYOS_KERNEL_VERSION"

# SIGN KERNEL with proper kernel keys
echo "Step 9: Signing kernel image..."
KERNEL_IMAGE="/boot/vmlinuz-${CACHYOS_KERNEL_VERSION}"

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "Kernel image not found at: $KERNEL_IMAGE"
    echo "Available kernel images:"
    ls /boot/vmlinuz-* 2>/dev/null
    exit 1
fi

# Now sign the kernel with proper kernel keys
if [ -f "$KERNEL_IMAGE" ]; then
    echo "Signing kernel with kernel signing key (PEM format)..."
    if sbsign --key "$KERNEL_PRIVATE_KEY" --cert "$KERNEL_PUBLIC_PEM" \
        --output "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE" 2>/dev/null; then
        mv "$KERNEL_IMAGE" "$KERNEL_IMAGE.unsigned"
        mv "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"
        echo "✅ Kernel image signed successfully"
    else
        echo "❌ Failed to sign kernel image with PEM certificate"
        echo "Continuing without kernel signing"
    fi
else
    echo "Error: Kernel image $KERNEL_IMAGE not found"
    exit 1
fi

# Update initramfs
echo "Step 10: Updating initramfs..."
dracut -f "/boot/initramfs-${CACHYOS_KERNEL_VERSION}.img" "$CACHYOS_KERNEL_VERSION"

# Update GRUB
echo "Step 11: Updating GRUB..."
grub2-mkconfig -o /boot/grub2/grub.cfg

# Create script to keep CachyOS as default after oficial fedora kernel updates
echo "Step 12: Creating script to keep CachyOS as default after updates..."
tee /etc/kernel/postinst.d/99-cachyos-default > /dev/null << 'EOF'
#!/bin/sh
# /etc/kernel/postinst.d/99-cachyos-default
# Set latest CachyOS kernel as default after kernel updates

set -e

# Find latest signed CachyOS kernel (excluding .unsigned and .backup files)
latest=$(ls /boot/vmlinuz-*-cachyos* 2>/dev/null | grep -v '\.unsigned\|\.backup' | sort -V | tail -n 1)

# Debug info
if [ -n "$latest" ]; then
    echo "Found CachyOS kernel: $latest"
    # Set as default
    if grubby --set-default="$latest"; then
        echo "✅ Set CachyOS kernel as default: $(basename "$latest")"
    else
        echo "❌ Failed to set default kernel"
        exit 1
    fi
else
    echo "⚠️  No CachyOS kernels found"
    exit 0
fi
EOF

chmod +x /etc/kernel/postinst.d/99-cachyos-default
echo "✅ Created script to automatically set CachyOS kernel as default after updates"

# Test the script works
echo "Testing CachyOS default script..."
/etc/kernel/postinst.d/99-cachyos-default

# Verify the default kernel
DEFAULT_KERNEL=$(grubby --default-kernel)
echo "Current default kernel: $DEFAULT_KERNEL"

if echo "$DEFAULT_KERNEL" | grep -q "cachyos"; then
    echo "✅ CachyOS kernel is set as default"
else
    echo "⚠️  CachyOS kernel is NOT the default - please check manually"
fi

# Enroll the kernel signing key (DER format) asking for PASSWORD
echo "Step 13: === KEY ENROLLMENT PASSWORD ===..."
mokutil --import $KERNEL_PUBLIC_DER

echo ""
echo "=== Phase 1 Complete ==="
echo "✅ CachyOS kernel $CACHYOS_KERNEL_VERSION installed"
echo ""
echo "1. REBOOT your system: sudo reboot"
echo "2. At the blue MOK screen:"
echo "   - Select 'Enroll MOK'"
echo "   - Select 'Continue'"
echo "   - Select 'Yes' to enroll the key"
echo "   - Enter the password if prompted"
echo "   - Select 'Reboot'"
echo ""
echo "3. After reboot, select the CachyOS kernel from GRUB menu"
echo "4. Run the NVIDIA setup: sudo ./2_nvidia_setup_after_reboot_cachyos.sh"

# ============================================================================
# CACHYOS PERFORMANCE TOOLS REFERENCE
# The following commands are available after CachyOS-settings installation.
# ============================================================================

# ----------------------------------------------------------------------------
# MONITORING TOOLS (No sudo required)
# ----------------------------------------------------------------------------

# Monitor memory usage by process (top 10 by default)
# topmem

# Show top 15 processes by memory
# topmem 15

# Sort by swap usage
# topmem --sort swap

# Monitor zram compression stats
# zramctl

# Quick kernel version and scheduler info
# kerver

# ----------------------------------------------------------------------------
# PCI LATENCY OPTIMIZATION (Requires sudo)
# ----------------------------------------------------------------------------

# Manually adjust PCI latency timers (already runs at boot via systemd)
# sudo pci-latency

# Check PCI latency service status
# systemctl status pci-latency.service --no-pager -l

# ----------------------------------------------------------------------------
# GAMING WRAPPERS - OpenGL via Vulkan (Mesa Zink)
# ----------------------------------------------------------------------------
# Use these to run OpenGL applications through Vulkan for better performance

# Run an OpenGL game via Vulkan
# zink-run /path/to/opengl-game

# Example with native Linux game
# zink-run ./game

# With Steam
# zink-run steam steam://rungameid/12345

# ----------------------------------------------------------------------------
# GAMING WRAPPERS - NVIDIA DLSS Optimization (NVIDIA GPUs only)
# ----------------------------------------------------------------------------
# Forces latest DLSS presets for Super Resolution, Ray Reconstruction, and Frame Generation

# Launch Steam game with DLSS optimization
# dlss-swapper steam steam://rungameid/12345

# Launch game executable with DLSS
# dlss-swapper /path/to/game.exe

# With Lutris
# dlss-swapper lutris lutris:rungame/game-name

# ----------------------------------------------------------------------------
# BORE SCHEDULER TUNING (Optional)
# ----------------------------------------------------------------------------
# Your CachyOS kernel has BORE scheduler enabled. To customize it:

# Create custom BORE configuration
# sudo nano /etc/sysctl.d/99-bore-custom.conf

# Add settings from the template (uncomment and adjust values):
# cat /usr/lib/sysctl.d/99-bore-scheduler.conf

# Apply custom BORE settings
# sudo sysctl --system

# ----------------------------------------------------------------------------
# VERIFY OPTIMIZATIONS
# ----------------------------------------------------------------------------

# Check key sysctl values
# sysctl vm.swappiness vm.dirty_bytes kernel.nmi_watchdog vm.vfs_cache_pressure fs.file-max

# Check if BORE scheduler is enabled (should return 1)
# cat /proc/sys/kernel/sched_bore

# Check zram swap status
# swapon --show
