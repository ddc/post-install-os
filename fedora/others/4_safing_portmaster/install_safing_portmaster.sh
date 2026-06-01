#!/usr/bin/env bash
#############################################################################
echo -e "\n\n INSTALLING Portmaster using nvidia keys"
# 1. Import repository key and add repo
sudo rpm --import https://updates.safing.io/latest/linux_amd64/portmaster.asc
sudo dnf config-manager --add-repo https://updates.safing.io/latest/linux_amd64/portmaster.rpm.repo

# 2. Install Portmaster
sudo dnf install -y portmaster

# 3. Sign Portmaster kernel module with EXISTING key (no new MOK needed)
sudo kmodsign sha512 /etc/pki/akmods/private/private_key.priv \
                     /etc/pki/akmods/certs/public_key.der \
                     $(modinfo -n portmaster 2>/dev/null || echo "/lib/modules/$(uname -r)/extra/portmaster.ko.xz")

# 4. Rebuild akmods to ensure module is properly built
sudo akmods --force

# 5. Enable and start service
sudo systemctl enable --now portmaster
#############################################################################
# Check if Portmaster module is loaded
lsmod | grep portmaster
# Verify the module signature
sudo modinfo portmaster | grep signature
#############################################################################
# # If SELinux blocks Portmaster:
# # Check for denials
# sudo ausearch -m avc -ts recent | grep portmaster
# # Create and apply custom SELinux policy if needed
# sudo audit2allow -a -M portmaster
# sudo semodule -i portmaster.pp
