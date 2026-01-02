#!/usr/bin/env bash
#############################################################################
set -e          # Exit on error
set -u          # Error on undefined variables
set -o pipefail # Pipe failures propagate
#############################################################################
ROUTER_CIFS="192.168.1.1/sda1"
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
mkdir -p "/home/$USER/tmp" 2>/dev/null || true
pushd "/home/$USER/tmp" || { log_error "Failed to change to tmp directory" 1>&2; exit 1; }
#############################################################################
function refresh_apt {
    sudo apt-get autoremove -y
    sudo apt-get update
    sudo apt-get --fix-broken install
    sudo snap refresh
}
function install_kept_back_pkgs {
    log_action "Checking for kept-back packages..."
    local list_kept_back
    list_kept_back=$(sudo apt-get upgrade --dry-run 2>/dev/null | sed -n 's/^ \([^ ]*\)/\1/p' | tr '\n' ' ')
    if [ -n "$list_kept_back" ]; then
        log_action "Installing kept-back packages: $list_kept_back"
        sudo apt-get install -y "$list_kept_back"
    else
        log_success "No kept-back packages found"
    fi
}
function upgrade {
    refresh_apt
    install_kept_back_pkgs
    sudo apt-get install -y -f
    sudo apt-get upgrade -y
    sudo apt-get dist-upgrade -y
    sudo apt-get full-upgrade -y
    #sudo do-release-upgrade -d
    sudo apt-get autoremove -y
    sudo apt-get clean
}
#############################################################################
log_action "Adding $USER to sudoers file"
if [ ! -f "/etc/sudoers.d/$USER" ]; then
    sudo /bin/su -c "cat <<EOF > /etc/sudoers.d/$USER
$USER ALL=(ALL:ALL) NOPASSWD: ALL
Defaults env_keep += \"SSH_AUTH_SOCK\"
EOF"
    if ! sudo visudo -c -f "/etc/sudoers.d/$USER"; then
        log_error "Sudoers file validation failed! Removing invalid file to prevent sudo lockout." 1>&2
        sudo rm -f "/etc/sudoers.d/$USER"
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
log_action "REMOVING Apps"
list_remove="kmahjongg, kmines, ksudoku, kpat, ktorrent, konversation, kdeconnect,
thunderbird, elisa, haruna, lximage-qt, skanlite, texdoctk, kio-gdrive, guvcview, v4l-utils,
colord-kde, kpatience, irqbalance, skanpage, libkdegames, libkf5kdegames-data,
kcontacts, libkf5contacts-data, libopenal-data, neochat"
for pkg in ${list_remove//,/ }; do
    log_info "Removing app: $pkg"
    sudo apt-get purge -y "$pkg" 2>/dev/null || true
done
#############################################################################
echo -e "\n\n>> REMOVING Libreoffice Apps"
list_remove_office="libreoffice, libreoffice-core, libreoffice-startcenter,
libreoffice-common, libreoffice-core-nogui, libreoffice-uiconfig-common,
libreoffice-style-colibre, libreoffice-style-breeze, libuno-sal3,
libuno-cppu3, libuno-purpenvhelpergcc3-3, libuno-cppuhelpergcc3-3,
libuno-salhelpergcc3-3, uno-libs-privatelibreoffice-uiconfig-calc,
libreoffice-uiconfig-draw, libreoffice-uiconfig-impress, libreoffice-uiconfig-mat,
libreoffice-uiconfig-writer, libuno-cppu3t64, libuno-purpenvhelpergcc3-3t64,
libuno-sal3t64, libuno-salhelpergcc3-3t64h, ure"
for pkg in ${list_remove_office//,/ }; do
    log_info "Removing libreoffice app: $pkg"
    sudo apt-get purge -y "$pkg" 2>/dev/null || true
done
#############################################################################
echo -e "\n\n>> REMOVING Snaps"
## removed: bare, gnome-42-2204, gnome-3-38-2004, core20, core22, firmware-updater, gtk-common-themes, snapd
list_remove_snaps="firefox, thunderbird"
for pkg in ${list_remove_snaps//,/ }; do
    log_info "Removing snap: $pkg"
    sudo snap remove "$pkg" 2>/dev/null || true
done
sudo apt-get purge -y snapd
#############################################################################
## removed: chromium-ffmpeg, skype, slack, teams-for-linux, spotify
# echo -e "\n\n>> INSTALLING Snaps"
# list_snaps="spotify"
# for pkg in ${list_snaps//,/ }; do
#     log_info "INSTALLING snap: $pkg"
#     sudo snap install "$pkg"
# done
#############################################################################
echo -e "\n\n>> Refreshing Apps"
refresh_apt
sleep 5
#############################################################################
## removed: ckb-next
echo -e "\n\n>> INSTALLING Apps"
list_apps="curl, pipx, git, git-extras, g++, valgrind, nmap, curl, wget, vim, synaptic, vlc, 7zip, 7zip-rar,
designer-qt6, gimp, samba, kleopatra, p7zip-full, figlet, cowsay, qbittorrent, gparted, piper,
cpufrequtils, ansible, kde-gtk-config, kde-spectacle, postgresql-client-common, okular,
postgresql-client, v4l2loopback-dkms, ffmpeg, obs-studio, filelight, guvcview, gh, virt-manager, filezilla"
for pkg in ${list_apps//,/ }; do
    log_info "INSTALLING app: $pkg"
    sudo apt-get install -y "$pkg"
done
#############################################################################
## removed: libicu-dev, lxqt-admin, policykit-1, libxcb-xtest0, ibus, libi2c-dev, ddcutil
echo -e "\n\n>> INSTALLING Libs"
list_libs="python3-dev, python3-pip, python-is-python3, libpython3-dev, python3-hvac, python3-tk, python3-pyqt6.qtsvg,
python3-mysql.connector, cython3, ntfs-3g, libffi-dev, pipenv, sqlite3, net-tools, gnupg, gnupg2, ifupdown, build-essential,
software-properties-common, coreutils, procps, ca-certificates, lsb-release, mysql-client, autotools-dev,
ffmpeg, network-manager-openvpn, apt-transport-https, pass, cmake, scdaemon, gdebi, perl-tk, cifs-utils,
libpoppler-cpp-dev, libnotify-bin, libbz2-dev, libsqlite3-dev, libboost-all-dev, libpq-dev, mtools, dosfstools,
libmysqlclient-dev, screen-resolution-extra, ibus, lm-sensors, cpu-checker, libldap2-dev, libsasl2-dev, unixodbc-dev,
libcurl4-openssl-dev, zlib1g-dev, liblzma-dev, libncurses5-dev, libreadline6-dev, libssl-dev, libgdbm-dev,
tk-dev, lzma, lzma-dev, extra-cmake-modules, v4l-utils, libaio1t64, libaio-dev, libudev-dev, usbutils"
for pkg in ${list_libs//,/ }; do
    log_info "Installing lib: $pkg"
    sudo apt-get install -y "$pkg"
done
#############################################################################
echo -e "\n\n>> INSTALLING Fonts"
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
list_fonts="ttf-mscorefonts-installer, texlive-latex-extra, texlive-fonts-extra,
texlive-fonts-recommended, texlive-luatex, fonts-lmodern, texlive-lang-portuguese,
libvlccore-dev, libvlc-dev, ubuntu-restricted-extras"
for pkg in ${list_fonts//,/ }; do
    log_info "Installing font: $pkg"
    sudo apt-get install -y "$pkg"
done
#############################################################################
echo -e "\n\n>> INSTALLING Python3 pipx libs for local user"
list_pipx="aws-sso-util, awsume, poetry, black, cprofilev, nvibrant"
for pkg in ${list_pipx//,/ }; do
    log_info "INSTALLING pipx: $pkg"
    pipx uninstall "$pkg"
    pipx install "$pkg"
done
sudo ln -sf "$HOME/.local/bin/poetry /usr/bin/poetry"
sudo ln -sf "$HOME/.local/bin/black /usr/bin/black"
echo -e "\n>> Configuring Poetry virtualenvs"
"$HOME/.local/bin/poetry" config virtualenvs.in-project true
#############################################################################
#echo -e "\n\n>> INSTALLING rclone"
#sudo apt-get install -y rclone
## rclone config
## rclone config file
#mkdir ~/GoogleDrive
#rclone mount gdrive: ~/GoogleDrive --daemon --vfs-cache-mode writes
#############################################################################
echo -e "\n\n>> INSTALLING virtualbox"
list_virtualbox="virtualbox, virtualbox-guest-additions-iso, virtualbox-guest-utils, virtualbox-ext-pack"
for pkg in ${list_virtualbox//,/ }; do
    log_info "INSTALLING virtualbox: $pkg"
    sudo apt-get install -y "$pkg"
done
sudo usermod -aG vboxusers "$USER"
#############################################################################
############################################################################# LOCAL ~/Programs
#############################################################################
echo -e "\n\n>> INSTALLING AWS cli"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
rm -rf "$HOME/Programs/aws-cli"
./aws/install -i "$HOME/Programs/aws-cli" -b "$HOME/.local/bin"
rm -rf ./aws*
#############################################################################
############################################################################# REPOS
#############################################################################
# echo -e "\n\n>> INSTALLING AZURE cli"
# sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
# sudo mkdir -p /usr/share/keyrings
# curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
# sudo chmod go+r /usr/share/keyrings/microsoft.gpg
#
# #AZ_DIST=$(lsb_release -cs)
# AZ_DIST=noble
# echo "Types: deb
# URIs: https://packages.microsoft.com/repos/azure-cli/
# Suites: ${AZ_DIST}
# Components: main
# Architectures: $(dpkg --print-architecture)
# Signed-by: /usr/share/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/azure-cli.sources
#
# refresh_apt
# sudo apt-get install -y azure-cli
#############################################################################
# echo -e "\n\n>> Fixing podman"
# echo -e "\n\n>>>> Adding docker hub to be usable in podman-compose"
# sudo apt-get install -y podman-compose
# echo unqualified-search-registries = [\"docker.io\"] | sudo tee -a /etc/containers/registries.conf
# #### use with pycharm -> unix:///run/user/1000/podman/podman-api.sock
# sudo apt-get install -y cpu-checker qemu-kvm
# sudo mkdir -p /usr/local/lib/podman
# sudo ln -sf $HOME/Programs/podman/podman /usr/local/bin/podman
# sudo ln -sf $HOME/Programs/podman/virtiofsd /usr/local/bin/virtiofsd
# sudo ln -sf $HOME/Programs/podman/gvproxy /usr/local/lib/podman/gvproxy
# sudo rm -rf $HOME/.config/containers
# sudo rm -rf $HOME/.local/share/containers
# podman system connection ls
# podman machine ls
# podman --log-level=debug machine init Podman
# podman --log-level=debug start Podman
#####################
### remove default
# podman --log-level=debug machine stop podman-machine-default
# podman --log-level=debug machine rm podman-machine-default
# podman --log-level=debug machine rm Podman
# podman --log-level=debug machine init Podman
# podman --log-level=debug start Podman
### set to root
#podman --log-level=debug machine init Podman --rootful=true
#podman system connection default Podman-root
#podman --log-level=debug machine set --rootful Podman
#podman --log-level=debug start Podman
#############################################################################
echo -e "\n\n>> INSTALLING msodbcsql18"
curl https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
#curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
curl https://packages.microsoft.com/config/ubuntu/24.10/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
refresh_apt
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18
sudo apt-get install -y unixodbc-dev unixodbc odbcinst
#############################################################################
echo -e "\n\n>> INSTALLING DOCKER"
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
sudo install -m 0755 -d /usr/share/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /usr/share/keyrings/docker.asc
sudo chmod a+r /usr/share/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
refresh_apt
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker "$USER"

sudo /bin/su -c 'cat <<EOF >> /etc/docker/daemon.json
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
EOF'

sudo systemctl unmask docker
sudo service docker start
#############################################################################
echo -e "\n\n>> Downloading custom docker-compose"
sudo apt-get purge -y docker-compose
sudo apt-get install -y docker-compose-plugin
local_path="$HOME/bin/docker-compose"
plugin_path=/usr/libexec/docker/cli-plugins/docker-compose
current_version=$($local_path --version | awk '{print $4}')
latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | sed -Ene '/^ *"tag_name": *"(v.+)",$/s//\1/p')
if [[ $current_version != "$latest_version" ]]; then
    echo -e "\n\n>> Updating docker-compose $current_version -> $latest_version"
    sudo rm -rf "$local_path"
    sudo curl -L "https://github.com/docker/compose/releases/download/$latest_version/docker-compose-linux-x86_64" -o "$local_path"
    sudo chmod 755 "$local_path"
    sudo rm -rf $plugin_path
    sudo cp "$local_path" $plugin_path
    sudo chmod 755 $plugin_path
    #sudo ln -sf $local_path /usr/local/bin/docker-compose
else
    echo -e "\n\n>> docker-compose is up to date"
fi
#############################################################################
echo -e "\n\n>> INSTALLING Spotify"
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
sleep 5
echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
refresh_apt
sudo apt-get install -y spotify-client
#############################################################################
echo -e "\n\n>> INSTALLING Brave Browser"
sudo apt install curl
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
refresh_apt
sudo apt-get install -y brave-browser
#############################################################################
echo -e "\n\n>> INSTALLING Unofficial Microsoft Teams client"
sudo mkdir -p /usr/share/keyrings
sudo wget -qO /usr/share/keyrings/teams-for-linux.asc https://repo.teamsforlinux.de/teams-for-linux.asc
sleep 5
sh -c 'echo "Types: deb\nURIs: https://repo.teamsforlinux.de/debian/\nSuites: stable\nComponents: main\nSigned-By: /usr/share/keyrings/teams-for-linux.asc\nArchitectures: amd64" | sudo tee /etc/apt/sources.list.d/teams-for-linux-packages.sources'
refresh_apt
sudo apt-get install -y teams-for-linux
#############################################################################
############################################################################# PPAs
#############################################################################
# echo -e "\n\n>> Adding Kubuntu ppa"
# sudo add-apt-repository -y ppa:kubuntu-ppa/backports
# sleep 5
# upgrade
#############################################################################
#echo -e "\n\n>> Adding GIT ppa"
#sudo add-apt-repository -y ppa:git-core/ppa
#sleep 5
#refresh_apt
#sudo apt-get install -y git
#############################################################################
echo -e "\n\n>> Adding openlinkhub ppa"
## http://localhost:27003
sudo add-apt-repository -y ppa:jurkovic-nikola/openlinkhub
sleep 5
refresh_apt
sudo apt-get install -y openlinkhub
#############################################################################
#echo -e "\n\n>> Adding globalprotect ppa"
## sudo add-apt-repository --remove ppa:yuezk/globalprotect-openconnect
##sudo apt-get install -y libwebkitgtk-6.0-4
#sudo apt-get install -y libwebkit2gtk-4.1-0 libxml2-dev
#sudo add-apt-repository -y ppa:yuezk/globalprotect-openconnect
#sleep 5
#refresh_apt
#sudo apt-get install -y globalprotect-openconnect
#############################################################################
############################################################################# Packages .deb
#############################################################################
echo -e "\n\n>> DOWNLOADING CHROME"
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
echo 'y' | sudo gdebi google-chrome-stable_current_amd64.deb
sudo rm -rf google-chrome-stable_current_amd64.deb
#############################################################################
echo -e "\n\n>> DOWNLOADING ZOOM"
wget https://zoom.us/client/latest/zoom_amd64.deb
echo 'y' | sudo gdebi ./zoom_amd64.deb
sudo rm -rf ./zoom_amd64.deb
#############################################################################
echo -e "\n\n>> DOWNLOADING DISCORD"
wget https://dl.discordapp.net/apps/linux/0.0.53/discord-0.0.53.deb -O discord.deb
echo 'y' | sudo gdebi ./discord.deb
sudo rm -rf ./discord.deb
#############################################################################
echo -e "\n\n>> DOWNLOADING 1PASSWORD"
wget https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb
echo 'y' | sudo gdebi ./1password-latest.deb
sudo rm -rf ./1password-latest.deb
#############################################################################
echo -e "\n\n>> DOWNLOADING TEAMVIEWER"
wget https://download.teamviewer.com/download/linux/teamviewer_amd64.deb
echo 'y' | sudo gdebi ./teamviewer_amd64.deb
rm -rf ./teamviewer_amd64.deb
#############################################################################
#echo -e "\n\n>> DOWNLOADING WPS OFFICE"
#wget https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11704/wps-office_11.1.0.11704.XA_amd64.deb -O wpsoffice.deb
#echo 'y' | sudo gdebi ./wpsoffice.deb
#sudo rm -rf ./wpsoffice.deb
#############################################################################
############################################################################# FILES
#############################################################################
#echo -e "\n\n>> Set /etc/environment"
#sudo /bin/su -c "cat <<EOF >> /etc/environment
#IDEA_PROPERTIES='$HOME/Programs/Jetbrains/data/intellij_linux.properties'
#IDEA_VM_OPTIONS='$HOME/Programs/Jetbrains/data/linux.vmoptions'
#CLION_PROPERTIES='$HOME/Programs/Jetbrains/data/clion_linux.properties'
#CLION_VM_OPTIONS='$HOME/Programs/Jetbrains/data/linux.vmoptions'
#PYCHARM_PROPERTIES='$HOME/Programs/Jetbrains/data/pycharm_linux.properties'
#PYCHARM_VM_OPTIONS='$HOME/Programs/Jetbrains/data/linux.vmoptions'
#DATAGRIP_PROPERTIES='$HOME/Programs/Jetbrains/data/datagrip_linux.properties'
#DATAGRIP_VM_OPTIONS='$HOME/Programs/Jetbrains/data/linux.vmoptions'
#PIPENV_VENV_IN_PROJECT=1
#PIPENV_VERBOSITY=-1
#EOF"
#sudo sed -i "s/'/\"/g" /etc/environment
#############################################################################
echo -e "\n\n>> Add ssd mount points to fstab"
sudo mkdir -p /media/Users
sudo mkdir -p /media/Windows
sudo mkdir -p /media/Games
sudo mkdir -p /mnt/router
sudo /bin/su -c "cat <<EOF >> /etc/fstab

# customs
UUID=6652C5F152C5C5D1 /media/Users ntfs uid=1000,gid=1000,file_mode=0755,dir_mode=0755 0 0
UUID=50C28318C2830208 /media/Windows ntfs uid=1000,gid=1000,file_mode=0755,dir_mode=0755 0 0
UUID=461E22781E2260E3 /media/Games ntfs uid=1000,gid=1000,file_mode=0755,dir_mode=0755 0 0
//${ROUTER_CIFS} /mnt/router cifs sec=none,uid=1000,gid=1000,vers=2.0,file_mode=0755,dir_mode=0755 0 0

EOF"
sudo systemctl daemon-reload
sudo mount -a
#############################################################################
echo -e "\n\n>> Disable memtest/uefi entries from grub"
sudo chmod 644 /etc/grub.d/20_memtest86+
sudo chmod 644 /etc/grub.d/30_uefi-firmware
#############################################################################
echo -e "\n\n>> Changing grub timeout and screen resolution"
sudo sed -i "s/.*GRUB_TIMEOUT.*/GRUB_TIMEOUT=5/g" /etc/default/grub
sudo sed -i "s/.*#GRUB_GFXMODE.*/GRUB_GFXMODE=1280x720/g" /etc/default/grub
echo "GRUB_RECORDFAIL_TIMEOUT=5" | sudo tee -a /etc/default/grub
sudo update-grub
#############################################################################
echo -e "\n\n>> Fix designer to use qt6 instead of qt5"
if [ -f /usr/lib/qt6/bin/designer ]; then
    sudo rm -rf /usr/bin/designer
    sudo ln -sf /usr/lib/qt6/bin/designer /usr/bin/designer
fi
#############################################################################
echo -e "\n\n>> Changing cpu frequency"
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sudo sed -i 's/.*GOVERNOR="ondemand"/GOVERNOR="performance"/g' /etc/init.d/cpufrequtils
sudo sed -i 's/MAX_SPEED="0"/MAX_SPEED="5500000"/g' /etc/init.d/cpufrequtils
sudo sed -i 's/MIN_SPEED="0"/MIN_SPEED="5500000"/g' /etc/init.d/cpufrequtils
sudo systemctl restart cpufrequtils.service
sudo systemctl daemon-reload
cat /proc/cpuinfo | grep -i mhz
#############################################################################
echo -e "\n\n>> Fixing nvidia"
sudo chmod 0755 /usr/share/screen-resolution-extra/nvidia-polkit
#############################################################################
############################################################################# OTHERS
#############################################################################
echo -e "\n\n>> Fix the missing search box in the synaptic toolbar"
sudo apt-get install -y apt-xapian-index
sudo update-apt-xapian-index -vf
sudo apt-get install --reinstall synaptic
sudo dpkg-reconfigure synaptic
#############################################################################
echo -e "\n\n>> Set RTC time to use local time to fix windows clock"
sudo timedatectl set-local-rtc 1 --adjust-system-clock
#############################################################################
#echo -e "\n\n>> Enabling firewalls"
#echo 'y' | sudo ufw reset
#sudo ufw enable
## docker
#sudo ufw allow in from any to 172.0.0.0/8
#sudo ufw allow out from 172.0.0.0/8 to any
## podman
#sudo ufw allow in from any to 10.88.0.0/16
#sudo ufw allow out from 10.88.0.0/16 to any
## kde connect
# sudo ufw allow 1714:1764/udp
# sudo ufw allow 1714:1764/tcp
#sudo ufw reload
#############################################################################
echo -e "\n\n>> Fixing chrome sandbox perms"
sudo chown root:ddc /home/ddc/Programs/Jetbrains/Clion/jbr/lib/chrome-sandbox
sudo chmod 4755 /home/ddc/Programs/Jetbrains/Clion/jbr/lib/chrome-sandbox

sudo chown root:ddc /home/ddc/Programs/Jetbrains/DataGrip/jbr/lib/chrome-sandbox
sudo chmod 4755 /home/ddc/Programs/Jetbrains/DataGrip/jbr/lib/chrome-sandbox

sudo chown root:ddc /home/ddc/Programs/Jetbrains/Pycharm/jbr/lib/chrome-sandbox
sudo chmod 4755 /home/ddc/Programs/Jetbrains/Pycharm/jbr/lib/chrome-sandbox

#sudo chown root:ddc /home/ddc/Programs/podman-desktop/chrome-sandbox
#sudo chmod 4755 /home/ddc/Programs/podman-desktop/chrome-sandbox
#############################################################################
echo -e "\n\n>> Adding user to kvm"
modprobe kvm
modprobe kvm_intel
sudo usermod -aG kvm "$USER"
#############################################################################
echo -e "\n\n>> Set /etc/sysctl.d/60-custom.conf"
sudo /bin/su -c "cat <<EOF > /etc/sysctl.d/60-custom.conf
## Set inotify watch limit high enough for IntelliJ IDEA
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 1048576

## 96MB shmmax shared
kernel.shmmax = 100663296

## 2MB shmall pages
kernel.shmall = 2097152

## max virtual memory
vm.max_map_count = 262144

## disable ipv6
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv6.conf.default.disable_ipv6 = 1
#net.ipv6.conf.lo.disable_ipv6 = 1

EOF"
sudo service procps restart
sudo sysctl -p --system
#############################################################################
echo -e "\n\n>> Set locales"
sudo /bin/su -c "cat <<EOF > /etc/default/locale
LANG=en_US.UTF-8
LANGUAGE=en_US.UTF-8
LC_ADDRESS=en_US.UTF-8
LC_IDENTIFICATION=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_TIME=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_COLLATE=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF"
#############################################################################
echo -e "\n\n>> Set /etc/security/limits.conf"
sudo /bin/su -c "cat <<EOF >> /etc/security/limits.conf

## Setting ulimit to 32767 to fix terminal in pycharm
* hard nofile 32767
root hard nofile 32767

EOF"
#############################################################################
## Create a /etc/gai.conf file to prefer IPv4 for dual-stack systems.
## This keeps IPv6 enabled but makes the system prefer IPv4 when both are available
echo -e "\n\n>> Prefer IPv4 over IPv6"
sudo tee /etc/gai.conf > /dev/null << 'EOF'
# Prefer IPv4 over IPv6
precedence ::ffff:0:0/96  100
EOF
#############################################################################
echo -e "\n\n>> Fix gnupg permissions"
chown -R "$USER" ~/.gnupg/
chmod -R 700 ~/.gnupg
#############################################################################
echo -e "\n\n>> Disabling pip kwallet/keyring"
python -m keyring --disable;
sudo python -m keyring --disable;
sudo apt-get remove python3-keychain -q -y >/dev/null
#sudo pip uninstall -y keyring
#############################################################################
echo -e "\n\n>> Turning off swap"
sudo swapoff -a
#############################################################################
#echo -e "\n\n>> Linking git to /usr/local/git"
#sudo ln -sf /home/ddc/Programs/git/bin/git /usr/local/git
#############################################################################
echo -e "\n\n>> Oracle instant client"
sudo sh -c "echo /home/ddc/Programs/oracle > /etc/ld.so.conf.d/oracle-instantclient.conf"
sudo ln -sf /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
sudo ldconfig
#############################################################################
#echo -e "\n\n>> Running upgrade"
#upgrade
#############################################################################
popd
echo -e "\n\n----> INSTALLATION COMPLETE <----\n\n"
# sleep 10 && sudo init 6
#############################################################################
#############################################################################
#############################################################################
# echo -e "\n\n>> Fix synaptic quick search"
#sudo add-apt-repository -y ppa:nrbrtx/synaptic
#sudo apt-get install -y synaptic
#sudo update-apt-xapian-index
#############################################################################
# echo -e "\n\n>> Creating rootless podman using docker.sock"
# # podman system service --time=0 tcp:localhost:2375 &
# podman system service --time=0 &
# sudo ln -sfvT /run/user/${UID}/podman/podman.sock /run/user/${UID}/docker.sock
#############################################################################
#echo -e "\n\n>> Shorten timeout from 90secs to 15secs"
#sudo sed -i "s/.*#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=15s/g" /etc/systemd/system.conf
#sudo sed -i "s/.*#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/g" /etc/systemd/system.conf
#sudo sed -i "s/.*#DefaultDeviceTimeoutSec.*/DefaultDeviceTimeoutSec=15s/g" /etc/systemd/system.conf
#sudo sed -i "s/kernel.yama.ptrace_scope = 1/kernel.yama.ptrace_scope = 0/g" /etc/sysctl.d/10-ptrace.conf
#############################################################################
# echo -e "\n\n>> INSTALLING CUDA"
# wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
# sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
# wget https://developer.download.nvidia.com/compute/cuda/12.2.2/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.2-535.104.05-1_amd64.deb
# sudo dpkg -i cuda-repo-ubuntu2204-12-2-local_12.2.2-535.104.05-1_amd64.deb
# sudo cp /var/cuda-repo-ubuntu2204-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
# refresh_apt
# sudo apt-get -y cuda
############################################################################# OK but this version of google drive is too slow
# echo -e "\n\n>> INSTALLING Gogle Drive"
# sudo add-apt-repository ppa:alessandro-strada/ppa
# sudo apt update && sudo apt install -y google-drive-ocamlfuse
# mkdir -p ~/GoogleDrive
# google-drive-ocamlfuse ~/GoogleDrive &
############################################################################# OK (already inside home)
# echo -e "\n\n>> INSTALLING Go"
# curl -LO https://go.dev/dl/go1.19.1.linux-amd64.tar.gz
# #rm -rf $HOME/Programs/go
# tar -C $HOME/Programs -xzf go1.19.1.linux-amd64.tar.gz
# rm -rf go1.19.1.linux-amd64.tar.gz
############################################################################# no need
# echo -e "\n\n>> INSTALLING OPENVPN"
# wget -O- https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/openvpn-repo-public.gpg
# echo "deb [arch=amd64 signed-by=/usr/share/keyrings/openvpn-repo-public.gpg] https://swupdate.openvpn.net/community/openvpn3/repos/ jammy main" | sudo tee /etc/apt/sources.list.d/openvpn3.list
# refresh_apt
# sudo apt-get install -y apt-transport-https openvpn3

## OLD WAY
# sudo wget https://swupdate.openvpn.net/repos/openvpn-repo-pkg-key.pub
# sudo apt-key add openvpn-repo-pkg-key.pub
# echo "deb [arch=amd64] https://swupdate.openvpn.net/community/openvpn3/repos/ jammy main" | sudo tee /etc/apt/sources.list.d/openvpn3.list
# refresh_apt
# sudo apt-get install -y openvpn3
############################################################################# can be installed downloading the package
# echo -e "\n\n>> INSTALLING OPERA"
# wget https://download3.operacdn.com/pub/opera/desktop/91.0.4516.16/linux/opera-stable_91.0.4516.16_amd64.deb
# sudo dpkg -i ./opera-stable_91.0.4516.16_amd64.deb
# rm -rf ./opera-stable_91.0.4516.16_amd64.deb
#############################################################################
############################################################################# NOTES
#############################################################################
### KATE Python syntax highlighting
# Settings -> Configure Kate... -> Open/Save -> Modes & Filetypes -> Filetype: Normal -> set "Variables:" ->  kate: syntax Python;
##############################
# Problem
# The problem is that with the "Ibus" input method, "Ctrl-shift-u" is by default configured to the "Unicode Code Point" shortcut.
# You can try this: Type ctrl-shift-u, then an (underlined) u appears.
# If you then type a unicode code point number in hex (e.g. 21, the ASCII/unicode CP for !) and press enter, it is replaced with the corresponding character.
#
# Example of ctr-shift-u
#
# Solution
# This shortcut can be changed or disabled using the ibus-setup utility:
#
# Run ibus-setup from the terminal (or open IBus Preferences).
# Go to “Emoji”.
# Next to “Unicode code point:”, click on the three dots (i.e. ...).
# In the dialog, click “Delete”, then “OK”.
# Close the IBus Preferences window.
