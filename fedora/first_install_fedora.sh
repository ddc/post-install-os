#!/usr/bin/env bash
#############################################################################
set -e          # Exit on error
set -u          # Error on undefined variables
set -o pipefail # Pipe failures propagate
#############################################################################
ROUTER_CIFS="192.168.1.1/sda1"
USE_1PASSWORD_SSH_AGENT=true
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
[[ $EUID -eq 0 ]] && log_error "Script cannot be run by root" && exit 1
#############################################################################
mkdir -p "$HOME/tmp" 2>/dev/null || true
pushd "$HOME/tmp" || { log_error "Failed to change to tmp directory" 1>&2; exit 1; }
#############################################################################
function refresh_dnf {
    sudo dnf clean all -y
    sudo dnf makecache -y
}
function refresh_flatpak {
    if command -v flatpak &> /dev/null; then
        log_action "Checking flatpak packages updates..."
        output=$(flatpak update --user -y 2>&1)
        if echo "$output" | grep -q "Updated"; then
            echo "$output"
        else
            log_success "Flatpak packages already up to date"
        fi
    fi
}
function upgrade {
    export DNF_RETRIES=3
    export DNF_TIMEOUT=5
    sudo dnf clean metadata -y
    sudo dnf upgrade -y --setopt=skip_if_unavailable=True --refresh || {
        log_warn "First upgrade attempt failed, cleaning all cache and retrying..."
        sudo dnf clean all -y
        sudo dnf upgrade -y --setopt=skip_if_unavailable=True
    }
    sudo dnf distro-sync -y --setopt=skip_if_unavailable=True
    sudo dnf autoremove -y
    refresh_dnf
}
#############################################################################
log_action "Adding $USER to sudoers file"
if [ ! -f /etc/sudoers.d/"$USER" ]; then
    sudo /bin/su -c "cat <<EOF > /etc/sudoers.d/${USER}
${USER} ALL=(ALL:ALL) NOPASSWD: ALL
Defaults env_keep += \"SSH_AUTH_SOCK\"
EOF"
    if ! sudo visudo -c -f /etc/sudoers.d/"$USER"; then
        log_error "Sudoers file validation failed! Removing invalid file to prevent sudo lockout." 1>&2
        sudo rm -f /etc/sudoers.d/"$USER"
        exit 1
    fi
    log_success "Sudoers file created and validated successfully"
else
    log_info "Sudoers file already exists, skipping"
fi
#############################################################################
log_action "Creating ansible dirs"
sudo mkdir -p /root/.ansible/tmp
sudo chmod 755 /root/.ansible/tmp
sudo mkdir -p "$HOME/.ansible/tmp"
sudo chmod 755 "$HOME/.ansible/tmp"
#############################################################################
log_action "Edit /etc/dnf/dnf.conf to limit number of kernels to keep installed"
## This will automatically keep only 2 kernels (current + 1 backup) on future kernel updates
if grep -q "^installonly_limit=" /etc/dnf/dnf.conf; then
    sudo sed -i 's/^installonly_limit=.*/installonly_limit=2/' /etc/dnf/dnf.conf
else
    echo "installonly_limit=2" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
fi
#############################################################################
log_action "ENABLING RPM Fusion repositories"
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
refresh_dnf
#############################################################################
log_action "REMOVING Apps"
list_remove="kmahjongg, kmines, ksudoku, kpat, ktorrent, konversation, kdeconnect,
korganizer, kwrite, kpatience, kdeconnectd, elisa, kamoso, lximage-qt,
skanlite, neochat, dragon, kontact, skanpage, akregator, kmail, kaddressbook,
elisa-player, guvcview, firefox, thunderbird"
for pkg in ${list_remove//,/ }; do
    log_info "Removing app: $pkg"
    sudo dnf remove -y "$pkg" 2>/dev/null || true
done
#############################################################################
log_action "REMOVING Libreoffice Apps"
sudo dnf group remove -y libreoffice 2>/dev/null || true
sudo dnf remove -y "libreoffice*" 2>/dev/null || true
list_remove_office="libreoffice, libreoffice-core, libreoffice-calc, libreoffice-draw,
libreoffice-impress, libreoffice-writer, libreoffice-math, libreoffice-base"
for pkg in ${list_remove_office//,/ }; do
    log_info "Removing: $pkg"
    sudo dnf remove -y "$pkg" 2>/dev/null || true
done
#############################################################################
refresh_dnf
upgrade
sleep 5
#############################################################################
############################################################################# INSTALLS
#############################################################################
## disabled: firefox, thunderbird, rpi-imager, pipx, podman-compose
log_action "INSTALLING Apps"
list_apps="curl, git, git-extras, gcc-c++, valgrind, nmap, wget, vim, vlc, p7zip, p7zip-plugins,
gimp, samba, kleopatra, qbittorrent, gparted, piper, ansible, kde-gtk-config, spectacle, zstd
kolourpaint, postgresql, obs-studio, filelight, guvcview, gh, figlet, cowsay, cpupower, fastfetch,
qt6-designer, okular, dnfdragora, plasma-firewall, texstudio, discord, fd, btop, filezilla, sshpass,
golang, asciidoc, kate, kdenlive, kgpg"
for pkg in ${list_apps//,/ }; do
    log_info "INSTALLING app: $pkg"
    sudo dnf install -y "$pkg"
done
#############################################################################
log_action "INSTALLING Libs"
list_libs="python3-devel, python3-pip, python3-tkinter, python3-mysql, python3-hvac, python3-passlib
mysql-connector-python3, Cython, ntfs-3g, libffi-devel, sqlite, net-tools, gnupg2,
NetworkManager-openvpn, dnf-plugins-core, cmake, perl-Tk, cifs-utils, poppler-cpp-devel,
libnotify, bzip2-devel, sqlite-devel, boost-devel, libpq-devel, mtools, dosfstools,
mysql-devel, screen, lm_sensors, libvirt-client, openldap-devel, cyrus-sasl-devel,
unixODBC-devel, libcurl-devel, zlib-devel, xz-devel, ncurses-devel, readline-devel,
openssl, openssl-devel, gdbm-devel, tk-devel, extra-cmake-modules, v4l-utils, dkms,
libaio, libaio-devel, libudev-devel, usbutils, kernel-devel, kernel-headers, pass,
ca-certificates, qt6-qtbase-devel, libva, libva-utils, pcsc-lite-devel, cabextract"
for pkg in ${list_libs//,/ }; do
    log_info "Installing lib: $pkg"
    sudo dnf install -y "$pkg"
done
#############################################################################
log_action "INSTALLING Fonts"
list_fonts="xorg-x11-font-utils, fontconfig, texlive-latex, texlive-latex-fonts,
google-noto-sans-fonts, google-noto-serif-fonts, liberation-fonts"
for pkg in ${list_fonts//,/ }; do
    log_info "Installing font: $pkg"
    sudo dnf install -y "$pkg"
done
#############################################################################
log_action "Installing Flatpak"
log_info "Cleaning up old flatpak installation"
flatpak remote-delete flathub --user 2>/dev/null || true
flatpak remote-delete flathub --system 2>/dev/null || true
rm -rf "$HOME/.local/share/flatpak"
sudo dnf install -y flatpak
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
refresh_flatpak
#############################################################################
log_action "INSTALLING Flatpak apps"
## disabled: floorp, eu.betterbird.Betterbird
## Application Data & Config: ~/.var/app
## Flatpak-specific directories: ~/.local/share/flatpak/app
## uninstall: flatpak uninstall --user --delete-data eu.betterbird.Betterbird
flatpak_apps="com.spotify.Client, org.onlyoffice.desktopeditors, us.zoom.Zoom,
com.github.IsmaelMartinez.teams_for_linux"
for pkg in ${flatpak_apps//,/ }; do
    log_info "Installing flatpak: $pkg"
    flatpak install --user -y flathub "$pkg"
done
#############################################################################
log_action "INSTALLING UV apps for local user"
list_uv="aws-sso-util, awsume, cprofilev, nvibrant, black, poetry"
log_info "Cleaning up old UV installation"
if command -v uv &> /dev/null; then
    for pkg in ${list_uv//,/ }; do
        uv tool uninstall "$pkg" 2>/dev/null || true
    done
fi
find "$HOME/.local/bin" -type l -lname "*/uv/tools/*" -delete 2>/dev/null || true
rm -rf "$HOME/.local/share/uv"
rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
curl -LsSf https://astral.sh/uv/install.sh | sh
for pkg in ${list_uv//,/ }; do
    log_info "Installing uv tool: $pkg"
    uv tool install "$pkg"
done
sudo ln -sf "$HOME/.local/bin/poetry" /usr/bin/poetry
sudo ln -sf "$HOME/.local/bin/black" /usr/bin/black
echo
log_info "Configuring Poetry virtualenvs"
"$HOME/.local/bin/poetry" config virtualenvs.in-project true
#############################################################################
# log_action "INSTALLING Pipx apps for local user"
# sudo dnf install -y pipx
# list_pipx="aws-sso-util, awsume, poetry, black, cprofilev, nvibrant"
# for pkg in ${list_pipx//,/ }; do
#     echo -e "\n>>>>> INSTALLING pipx:" "$pkg"
#     pipx uninstall "$pkg"
#     pipx install "$pkg"
# done
# sudo ln -sf "$HOME/.local/bin/poetry /usr/bin/poetry"
# sudo ln -sf "$HOME/.local/bin/black /usr/bin/black"
#############################################################################
# log_action "INSTALLING virtualbox from rpmfusion without secure boot"
# sudo dnf install -y virtualbox virtualbox-guest-additions
# sudo usermod -a -G vboxusers "${USER}"
# sudo systemctl enable vboxdrv
# sudo systemctl restart vboxdrv
#############################################################################
# log_action "Installing Qemu/KVM Virtual Machine Manager"
# sudo dnf install -y virt-manager
# ## disabling STP
# sudo virsh net-dumpxml default | sed "s/stp='on'/stp='off'/" | sudo virsh net-define /dev/stdin
# sudo virsh net-destroy default && sudo virsh net-start default
# ## sudo virsh net-dumpxml default | grep bridge
# echo "Adding "${USER}" user to kvm"
# sudo modprobe kvm
# sudo modprobe kvm_intel
# sudo usermod -aG kvm "${USER}"
# sudo usermod -aG libvirt "${USER}"
#############################################################################
log_action "INSTALLING gp-saml-gui"
## gp-saml-gui is a Python script used for interactive SAML authentication with GlobalProtect VPNs
sudo dnf install -y python3-gobject gtk4-devel webkit2gtk4.1-devel wmctrl
uv tool install https://github.com/dlenski/gp-saml-gui/archive/master.zip
#############################################################################
log_action "INSTALLING ffmpeg (full version from RPM Fusion)"
## Replace ffmpeg-free with full ffmpeg from RPM Fusion for all codec support
sudo dnf install -y ffmpeg ffmpeg-libs --allowerasing
#############################################################################
log_action "INSTALLING AWS cli"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
rm -rf "$HOME/Programs/aws-cli"
./aws/install -i "$HOME/Programs/aws-cli" -b "$HOME/.local/bin"
rm -rf ./aws*
#############################################################################
log_action "INSTALLING msodbcsql18"
sudo dnf config-manager addrepo --overwrite --from-repofile=https://packages.microsoft.com/config/rhel/9/prod.repo
refresh_dnf
sudo ACCEPT_EULA=Y dnf install -y --assumeyes msodbcsql18
sudo ACCEPT_EULA=Y dnf install -y --assumeyes mssql-tools18
sudo dnf install -y unixODBC-devel
sudo dnf install -y unixODBC
#############################################################################
log_action "Excluding moby packages from Microsoft repository to prevent Docker CE conflicts"
sudo sed -i '/repo_gpgcheck=1/a exclude=moby-cli moby-engine moby-buildx moby-compose' /etc/yum.repos.d/mssql-release.repo 2>/dev/null || true
#############################################################################
log_action "INSTALLING DOCKER"
sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
sudo rm -f /etc/yum.repos.d/docker-ce.repo
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
refresh_dnf
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
sudo ln -sf /usr/libexec/docker/cli-plugins/docker-compose "$HOME/bin/docker-compose"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-level": "warn",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "default-address-pools": [
    {
      "base" : "172.0.0.0/8",
      "size" : 24
    }
  ]
}
EOF

# sudo mkdir -p /etc/systemd/system/docker.service.d
# sudo tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<'EOF'
# [Service]
# Environment=DOCKER_MIN_API_VERSION=1.24
# EOF

sudo systemctl daemon-reload
sudo systemctl unmask docker
sudo systemctl enable docker
sudo systemctl restart docker

#sudo systemctl status docker
#rpm -q docker-ce docker-ce-cli
#############################################################################
# log_action "INSTALLING ddcutil"
# sudo dnf copr enable -y rockowitz/ddcutil
# sudo dnf install -y qt6-qtbase-devel qt6-qttools-devel qt6-linguist
# sudo dnf install -y ddcutil ddcutil-devel glib2-devel pkgconfig cmake gcc-c++
# mkdir build && cd build
# cmake -DUSE_QT6=ON -DCMAKE_INSTALL_PREFIX="$HOME/Programs/ddcui"
# cmake --build . -j$(nproc)
# cmake --install .
## sudo dnf copr delete -y rockowitz/ddcutil
#############################################################################
log_action "INSTALLING OpenLinkHub"
sudo dnf copr enable -y jurkovic-nikola/OpenLinkHub
refresh_dnf
sudo dnf install -y OpenLinkHub
## service configuration that will ensure OpenLinkHub starts after USB devices are fully initialized at boot
sudo mkdir -p /etc/systemd/system/OpenLinkHub.service.d
sudo tee /etc/systemd/system/OpenLinkHub.service.d/override.conf > /dev/null << 'EOF'
[Unit]
# Wait for basic system initialization and devices
After=basic.target
After=sysinit.target
Wants=basic.target

[Service]
# Allow time for USB device enumeration and initialization
ExecStartPre=/bin/sleep 5
EOF
sudo systemctl daemon-reload
sudo systemctl restart OpenLinkHub
sudo systemctl enable OpenLinkHub
sudo systemctl is-enabled OpenLinkHub
# journalctl -u OpenLinkHub --boot=0 --no-pager
# echo -e "\n✓ Done! Access OpenLinkHub at: http://localhost:27003"
#############################################################################
#log_action "Installing Steam"
#sudo dnf config-manager setopt rpmfusion-nonfree-steam.enabled=1
#sudo dnf install -y steam
#############################################################################
log_action "INSTALLING CHROME"
sudo dnf config-manager setopt google-chrome.enabled=1
sudo dnf install -y google-chrome-stable
#############################################################################
log_action "INSTALLING Brave Browser Release Version"
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo dnf install -y brave-browser
#############################################################################
log_action "INSTALLING LibreWolf"
sudo dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf install -y librewolf
#############################################################################
log_action "INSTALLING 1PASSWORD"
sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
sudo dnf install -y 1password
#############################################################################
#log_action "INSTALLING globalprotect-openconnect"
#sudo dnf copr enable -y yuezk/globalprotect-openconnect
#refresh_dnf
#sudo dnf install -y globalprotect-openconnect
#############################################################################
#log_action "DOWNLOADING TEAMVIEWER"
#sudo dnf install -y https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm
#############################################################################
############################################################################# OTHERS
#############################################################################
log_action "Enabling auto-login for user $USER"
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/kde_settings.conf > /dev/null <<EOF
[Autologin]
Relogin=false
Session=plasma
User=${USER}

[General]
HaltCommand=
RebootCommand=

[Theme]
Current=01-breeze-fedora

[Users]
MaximumUid=60000
MinimumUid=1000
EOF
#############################################################################
log_action "Add ssd mount points to fstab"
sudo mkdir -p /media/router
if ! grep -q "${ROUTER_CIFS}" /etc/fstab; then
    sudo /bin/su -c "cat <<EOF >> /etc/fstab
## customs
//${ROUTER_CIFS} /media/router cifs user,noauto,sec=none,uid=1000,gid=1000,vers=2.0,file_mode=0755,dir_mode=0755 0 0
EOF"
    log_success "Added router mount to fstab"
else
    log_info "Router mount already in fstab, skipping"
fi
sudo chmod u+s /usr/bin/mount.cifs
sudo systemctl daemon-reload
sudo mount -a 2>/dev/null || true
#############################################################################
log_action "GRUB - Disable memtest/uefi entries"
sudo chmod 644 /etc/grub.d/20_memtest86+ 2>/dev/null || true
sudo chmod 644 /etc/grub.d/30_uefi-firmware 2>/dev/null || true
log_action "GRUB - Changing timeout and screen resolution"
if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
    sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/" /etc/default/grub
else
    echo "GRUB_TIMEOUT=5" | sudo tee -a /etc/default/grub > /dev/null
fi
if ! grep -q "^GRUB_GFXPAYLOAD_LINUX" /etc/default/grub; then
    echo "GRUB_GFXPAYLOAD_LINUX=keep" | sudo tee -a /etc/default/grub > /dev/null
fi
if ! grep -q "^GRUB_GFXMODE" /etc/default/grub; then
    echo "GRUB_GFXMODE=1920x1080" | sudo tee -a /etc/default/grub > /dev/null
fi
if ! grep -q "^GRUB_RECORDFAIL_TIMEOUT" /etc/default/grub; then
    echo "GRUB_RECORDFAIL_TIMEOUT=5" | sudo tee -a /etc/default/grub > /dev/null
fi
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
#############################################################################
log_action "Changing cpu frequency"
sudo systemctl enable cpupower
sudo cpupower frequency-set -g performance
sudo systemctl start cpupower
grep -i mhz /proc/cpuinfo
#############################################################################
log_action "Set RTC time to use local time to fix windows clock"
sudo timedatectl set-local-rtc 1 --adjust-system-clock
#############################################################################
log_action "Enabling firewalls" ## docker and podman ips
sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" source address="172.0.0.0/8" accept'
sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" destination address="172.0.0.0/8" accept'
sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" source address="10.88.0.0/16" accept'
sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" destination address="10.88.0.0/16" accept'
sudo firewall-cmd --reload
## sudo firewall-cmd --zone=FedoraWorkstation --list-rich-rules
#############################################################################
log_action "Fixing chrome sandbox perms"
sudo chown root:ddc "$HOME/Programs/Jetbrains/Clion/jbr/lib/chrome-sandbox" 2>/dev/null || true
sudo chmod 4755 "$HOME/Programs/Jetbrains/Clion/jbr/lib/chrome-sandbox" 2>/dev/null || true

sudo chown root:ddc "$HOME/Programs/Jetbrains/DataGrip/jbr/lib/chrome-sandbox" 2>/dev/null || true
sudo chmod 4755 "$HOME/Programs/Jetbrains/DataGrip/jbr/lib/chrome-sandbox" 2>/dev/null || true

sudo chown root:ddc "$HOME/Programs/Jetbrains/Pycharm/jbr/lib/chrome-sandbox" 2>/dev/null || true
sudo chmod 4755 "$HOME/Programs/Jetbrains/Pycharm/jbr/lib/chrome-sandbox" 2>/dev/null || true
#############################################################################
log_action "Adding docker hub to be usable in podman-compose"
if [ -f /etc/containers/registries.conf ]; then
    if ! grep -q 'unqualified-search-registries.*docker.io' /etc/containers/registries.conf; then
        echo 'unqualified-search-registries = ["docker.io"]' | sudo tee -a /etc/containers/registries.conf > /dev/null
        log_success "Added docker.io to registries.conf"
    else
        log_info "docker.io already in registries.conf, skipping"
    fi
else
    log_warn "registries.conf not found, skipping"
fi
#############################################################################
log_action "Set /etc/sysctl.d/60-custom.conf"
sudo tee /etc/sysctl.d/60-custom.conf > /dev/null << 'EOF'
## Set inotify watch limit high enough for IntelliJ IDEA and other JetBrains IDEs
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 1048576
EOF
sudo sysctl -p /etc/sysctl.d/60-custom.conf
#############################################################################
log_action "Set PAM limits"
if ! grep -q "^${USER}.*nofile.*32767" /etc/security/limits.conf; then
    sudo tee -a /etc/security/limits.conf > /dev/null << EOF
## Setting ulimit to 32767 to fix terminal in pycharm
${USER} soft nofile 32767
${USER} hard nofile 32767
## Setting memory to unlimited
${USER} soft memlock unlimited
${USER} hard memlock unlimited
EOF
    log_success "Added PAM limits to limits.conf"
else
    log_info "PAM limits already configured, skipping"
fi

## Systemd user limits
sudo mkdir -p /etc/systemd/user.conf.d
if [ ! -f /etc/systemd/user.conf.d/limits.conf ]; then
    sudo tee /etc/systemd/user.conf.d/limits.conf > /dev/null << 'EOF'
[Manager]
DefaultLimitNOFILE=32767:32767
DefaultLimitMEMLOCK=infinity
EOF
    log_success "Created systemd user limits configuration"
else
    log_info "Systemd user limits already configured, skipping"
fi
## ulimit -n  # Should show 32767
## ulimit -l  # Should show unlimited
#############################################################################
log_action "Prefer IPv4 over IPv6"
## Create a /etc/gai.conf file to prefer IPv4 for dual-stack systems.
## This keeps IPv6 enabled but makes the system prefer IPv4 when both are available
sudo tee /etc/gai.conf > /dev/null << 'EOF'
## Prefer IPv4 over IPv6
precedence ::ffff:0:0/96  100
EOF
#############################################################################
log_action "Set locales"
sudo localectl set-locale LANG=en_US.UTF-8
#############################################################################
log_action "Fix gnupg directory permissions"
chown -R "$USER" "$HOME/.gnupg" 2>/dev/null || true
chmod -R 700 "$HOME/.gnupg" 2>/dev/null || true
#############################################################################
log_action "Fix ssh config file permissions"
chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
#############################################################################
log_action "Set hostname to ddcx"
sudo hostnamectl set-hostname ddcx
sudo systemctl restart systemd-hostnamed
#############################################################################
log_action "Disabling pip kwallet/keyring"
python -m keyring --disable 2>/dev/null || true
sudo python -m keyring --disable 2>/dev/null || true
#############################################################################
log_action "Load Oracle instant client"
sudo sh -c "echo $HOME/Programs/oracle > /etc/ld.so.conf.d/oracle-instantclient.conf"
sudo ldconfig
#############################################################################
log_action "Disable NetworkManager-wait-online (Saves ~5.5s on boot time)"
sudo systemctl disable NetworkManager-wait-online.service
#############################################################################
log_action "Disabling WiFi MAC address randomization for static IP reliability"
wifi_connection=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep 'wireless' | cut -d: -f1 | head -1)
if [ -n "$wifi_connection" ]; then
    log_info "Found active WiFi connection: $wifi_connection"
    current_mac_setting=$(nmcli connection show "$wifi_connection" | grep '802-11-wireless.cloned-mac-address:' | awk '{print $2}')
    if [ "$current_mac_setting" != "permanent" ]; then
        log_action "MAC randomization is enabled (current: $current_mac_setting), disabling..."
        # Disable MAC randomization
        sudo nmcli connection modify "$wifi_connection" 802-11-wireless.cloned-mac-address permanent
        # Apply the change by reconnecting
        log_action "Reconnecting to WiFi to apply changes..."
        sudo nmcli connection down "$wifi_connection" && sudo nmcli connection up "$wifi_connection"
        log_success "WiFi MAC randomization disabled - using permanent hardware MAC address"
    else
        log_success "WiFi already using permanent MAC address"
    fi
else
    log_warn "No active WiFi connection found, skipping MAC randomization fix"
fi
#############################################################################
log_action "Checking swap configuration"
if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -gt 60000000 ]; then
  log_info "System has >60GB RAM, disabling swap for performance"
  sudo swapoff -a
else
  log_info "System has <60GB RAM, keeping swap enabled"
fi
#############################################################################
if [ "$USE_1PASSWORD_SSH_AGENT" = "true" ]; then
    log_action "Configuring 1Password SSH agent"

    # Verify 1Password is installed
    if ! command -v 1password &> /dev/null; then
        log_warn "1Password not found - install it first before using SSH agent"
    else
        # Disable systemd SSH agent
        log_info "Disabling systemd SSH agent"
        systemctl --user stop ssh-agent.service 2>/dev/null || true
        systemctl --user disable ssh-agent.service 2>/dev/null || true
        systemctl --user stop ssh-agent.socket 2>/dev/null || true
        systemctl --user disable ssh-agent.socket 2>/dev/null || true

        # Configure shell to use 1Password SSH agent
        log_info "Configuring shell to use 1Password SSH agent"
        if [ -f "$HOME/.shellrc" ]; then
            # Check if SSH_AUTH_SOCK is already configured for 1Password
            if ! grep -q "SSH_AUTH_SOCK.*1password.*agent.sock" "$HOME/.shellrc"; then
                # Add 1Password SSH agent configuration
                sed -i '/^#* *1Password SSH Agent/,/^export SSH_AUTH_SOCK/d' "$HOME/.shellrc" 2>/dev/null || true
                sed -i '/^case \$- in/a\
\
#######################################################\
# 1Password SSH Agent\
#######################################################\
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"\
' "$HOME/.shellrc"
                log_success "Added 1Password SSH agent to $HOME/.shellrc"
            else
                log_info "1Password SSH agent already configured in $HOME/.shellrc"
            fi
        else
            log_warn "$HOME/.shellrc not found - SSH_AUTH_SOCK not configured"
        fi

        log_success "1Password SSH agent configured"
    fi
fi
#############################################################################
log_action "Reloading systemd..."
sudo systemctl daemon-reload
## After reboot, run: systemd-analyze
#############################################################################
### .p10k.zsh file is responsible for PS1 and themes
log_action "Changing default $USER shell from bash to zsh"
sudo dnf install -y zsh
sudo usermod -s "$(which zsh)" "$USER"

log_info "Cloning the Shell Framework (Oh My Zsh)"
sudo rm -rf "$HOME/.oh-my-zsh"
git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"

log_info "Cloning powerlevel10k zsh theme"
sudo rm -rf "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

log_info "Cloning zsh-syntax-highlighting"
sudo rm -rf "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
# #############################################################################
log_action "Changing default root shell from bash to zsh"
sudo usermod -s "$(which zsh)" root
log_action "Copying zsh files to root user"
sudo cp -R "$HOME/.oh-my-zsh" /root
sudo cp "$HOME/.oh-my-zsh.zsh" /root
sudo cp "$HOME/.zshrc" /root
sudo cp "$HOME/.p10k.zsh" /root
sudo cp "$HOME/.shellrc" /root
sudo cp "$HOME/.vimrc" /root
sudo cp "$HOME/.bashrc" /root
#############################################################################
log_action "Refreshing KDE menu and desktop database"
log_info "This ensures custom applications appear correctly after reinstall"
log_warn "DO NOT click 'Edit -> Restore to system menu' in kmenuedit - it will delete all custom apps!"
kbuildsycoca6 --noincremental 2>/dev/null || log_warn "kbuildsycoca6 not found, skipping KDE cache rebuild"
update-desktop-database ~/.local/share/applications/ 2>/dev/null || log_warn "update-desktop-database failed, skipping"
gtk-update-icon-cache -f ~/.local/share/icons/ 2>/dev/null || log_info "Icon cache update skipped (directory may not exist)"
log_success "KDE menu refresh completed"
#############################################################################
#log_action "Configure SELinux (optional - set to permissive for development)"
# sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
#############################################################################
# log_action "Fixing firefox SELinux"
# mkdir -p "$HOME/.mozilla/firefox/*/gmp-widevinecdm" 2>/dev/null || true
# sudo restorecon -R "$HOME/.mozilla/firefox" 2>/dev/null || true
#############################################################################
popd || { log_error "Failed to return to previous directory" 1>&2; exit 1; }
echo
log_success "INSTALLATION COMPLETED!"
echo
#############################################################################
log_warn "REBOOTING IN 10 SECONDS TO APPLY ALL CHANGES..."
sleep 10 && sudo reboot
#############################################################################
#############################################################################
#############################################################################
# NOTES
#############################################################################
## DNF Repos
### list:       dnf repolist --all
### enable:     sudo dnf config-manager setopt rpmfusion-nonfree-steam.enabled=1
### add:        sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
### remove:     sudo rm /etc/yum.repos.d/brave-browser.repo
#############################################################################
## KATE Python syntax highlighting
# Settings -> Configure Kate... -> Open/Save -> Modes & Filetypes -> Filetype: Normal -> "Variables:" ->  kate: syntax Python;
#############################################################################
## IBUS Problem
# The problem is that with the "Ibus" input method, "Ctrl-shift-u" is by default configured to the "Unicode Code Point" shortcut.
# You can try this: Type ctrl-shift-u, then an (underlined) u appears.
# If you then type a unicode code point number in hex (e.g. 21, the ASCII/unicode CP for !) and press enter, it is replaced with the corresponding character.
#
# Example of ctr-shift-u
#
# Solution
# This shortcut can be changed or disabled using the ibus-setup utility:
# Run ibus-setup from the terminal (or open IBus Preferences).
# Go to "Emoji".
# Next to "Unicode code point:", click on the three dots (i.e. ...).
# In the dialog, click "Delete", then "OK".
# Close the IBus Preferences window.
