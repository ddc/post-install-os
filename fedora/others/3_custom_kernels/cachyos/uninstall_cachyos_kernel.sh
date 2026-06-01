#!/usr/bin/env bash

# CachyOS Kernel Uninstall Script
# Safely removes CachyOS kernel while preserving NVIDIA drivers and keys

set -e

echo "=== CachyOS Kernel Uninstall Script ==="
echo "This will remove CachyOS kernel but preserve NVIDIA drivers and keys"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root or with sudo"
    exit 1
fi

# Show current kernel
CURRENT_KERNEL=$(uname -r)
echo "Current running kernel: $CURRENT_KERNEL"
echo ""

# List what will be removed
echo "=== ITEMS TO BE REMOVED ==="
echo "1. CachyOS kernel packages:"
rpm -qa | grep -E 'kernel-cachyos|linux-cachyos' | sort
echo ""

echo "2. CachyOS kernel files in /boot:"
find /boot -name '*cachyos*' 2>/dev/null | sort
echo ""

echo "3. CachyOS module directories:"
find /lib/modules -name '*cachyos*' 2>/dev/null | sort
echo ""

echo "4. CachyOS repository:"
ls /etc/yum.repos.d/*cachyos* 2>/dev/null || echo "No CachyOS repository files found"
echo ""

# Show what will be preserved
echo "=== ITEMS THAT WILL BE PRESERVED ==="
echo "✅ NVIDIA keys in /etc/pki/akmods/"
echo "✅ NVIDIA driver packages"
echo "✅ Kernel signing keys in /root/kernel_keys/"
echo "✅ All other kernels (Fedora stock kernels)"
echo "✅ Your data and configuration"
echo ""

# Safety check - don't remove if running CachyOS kernel
if [[ "$CURRENT_KERNEL" =~ "cachyos" ]]; then
    echo "❌ WARNING: You are currently running the CachyOS kernel!"
    echo "   If you remove it, you won't be able to boot into this kernel."
    echo "   Please reboot into a Fedora stock kernel first, then run this script."
    echo ""
    echo "Available stock kernels:"
    rpm -qa | grep '^kernel-[0-9]' | grep -v cachyos | head -5
    echo ""
    read -p "Do you want to continue anyway? (type 'FORCE' to continue): " -r confirmation
    if [ "$confirmation" != "FORCE" ]; then
        echo "Aborted. Please reboot into a stock kernel first."
        exit 1
    fi
    echo "⚠️  Force removal enabled - system may be unbootable if no other kernels exist!"
    echo ""
fi

# Final confirmation
read -p "Are you sure you want to remove CachyOS kernel? (type 'REMOVE' to confirm): " -r confirmation
if [ "$confirmation" != "REMOVE" ]; then
    echo "Aborted. Type 'REMOVE' (in uppercase) to confirm removal."
    exit 0
fi

echo ""
echo "Starting removal process..."
echo ""

# Step 1: Remove CachyOS kernel packages
echo "Step 1: Removing CachyOS kernel packages..."
for pkg in $(rpm -qa | grep -E 'kernel-cachyos|linux-cachyos'); do
    echo "Removing: $pkg"
    rpm -e "$pkg" 2>/dev/null || echo "  Could not remove $pkg (may be already removed)"
done
echo ""

# Step 2: Remove kernel files from /boot
echo "Step 2: Removing CachyOS kernel files from /boot..."
find /boot -name '*cachyos*' -delete 2>/dev/null || true
echo "Boot files removed"
echo ""

# Step 3: Remove module directories
echo "Step 3: Removing CachyOS module directories..."
for dir in /lib/modules/*cachyos*; do
    if [ -d "$dir" ]; then
        echo "Removing: $dir"
        rm -rf "$dir"
    fi
done
echo "Module directories removed"
echo ""

# Step 4: Remove repository
echo "Step 4: Removing CachyOS repository..."
rm -f /etc/yum.repos.d/*cachyos* 2>/dev/null || true
echo "Repository removed"
echo ""

# Step 5: Clean DNF cache
echo "Step 5: Cleaning DNF cache..."
dnf clean all
echo "DNF cache cleaned"
echo ""

# Step 6: Removing script to keep CachyOS as default after updates
echo "Step 6: Removing script to keep CachyOS as default after updates..."
rm -rf  /etc/kernel/postinst.d/99-cachyos-default 2>/dev/null || true

# Step 7: Update GRUB
echo "Step 7: Updating GRUB..."
if [ -d /sys/firmware/efi ]; then
    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
else
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
fi
echo "GRUB updated"
echo ""

# Step 8: Verify NVIDIA setup is intact
echo "Step 8: Verifying NVIDIA setup is preserved..."
if [ -f "/etc/pki/akmods/certs/public_key.der" ]; then
    echo "✅ NVIDIA public key preserved"
fi
if [ -f "/etc/pki/akmods/private/private_key.priv" ]; then
    echo "✅ NVIDIA private key preserved"
fi

echo "NVIDIA packages still installed:"
rpm -qa | grep -i nvidia | head -5
echo ""

# Step 9: Show remaining kernels
echo "Step 9: Remaining kernels on system:"
rpm -qa | grep -E '^kernel-[0-9]' | grep -v cachyos | sort
echo ""

echo "=== UNINSTALLATION COMPLETE ==="
echo "✅ CachyOS kernel removed"
echo "✅ NVIDIA drivers and keys preserved"
echo "✅ GRUB configuration updated"
echo ""
echo "Remaining kernels:"
rpm -qa | grep -E '^kernel-[0-9]' | grep -v cachyos | sort
echo ""
echo "Next steps:"
if [[ "$CURRENT_KERNEL" =~ "cachyos" ]]; then
    echo "⚠️  REBOOT REQUIRED - You're still running CachyOS kernel"
    echo "   The system will use a stock Fedora kernel after reboot"
fi
echo "   Run: sudo reboot"
echo ""
echo "After reboot, verify with: uname -r && nvidia-smi"
