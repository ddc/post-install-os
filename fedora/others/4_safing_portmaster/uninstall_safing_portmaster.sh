#!/usr/bin/env bash
#############################################################################
echo -e "\n\n UNINSTALLING Portmaster"

# 1. Stop and disable Portmaster service
sudo systemctl stop portmaster
sudo systemctl disable portmaster

# 2. Remove Portmaster package
sudo dnf remove -y portmaster portmaster-akmod

# 3. Remove Portmaster kernel modules
sudo rm -f /lib/modules/*/extra/portmaster*.ko*
sudo rm -f /usr/lib/modules/*/extra/portmaster*.ko*

# 4. Remove Portmaster configuration files and data
sudo rm -rf /etc/portmaster/
sudo rm -rf /opt/safing/portmaster/
sudo rm -rf /var/lib/portmaster/
sudo rm -rf ~/.config/portmaster/
sudo rm -rf ~/.cache/portmaster/

# 5. Remove Portmaster repository
sudo rm -f /etc/yum.repos.d/portmaster*.repo

# 6. Remove Portmaster GPG key (optional - only if you want to)
sudo rpm -e gpg-pubkey-$(rpm -qa gpg-pubkey | grep -i safing | cut -d- -f3) 2>/dev/null || true

# 7. Rebuild kernel module dependencies
sudo depmod -a

# 8. Remove any leftover SELinux policies
sudo semodule -l | grep portmaster | while read policy; do
    sudo semodule -r $policy 2>/dev/null
done

echo -e "\n Portmaster has been completely removed."
echo " You may want to reboot to ensure all kernel modules are unloaded."






# # Firewall Rules: Portmaster may have added firewall rules. Check and remove if needed:
# sudo nft list ruleset | grep -i portmaster
# sudo iptables-save | grep -i portmaster
#
# # NetworkManager Integration: If Portmaster modified NetworkManager:
# # Check for Portmaster DNS settings
# nmcli connection show --active | grep -i portmaster
