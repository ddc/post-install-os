#!/usr/bin/env bash
#############################################################################
# install_functions.sh - Individually callable install functions
# Source this file and call functions explicitly. Nothing runs on source.
#############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#############################################################################
ROUTER_CIFS="192.168.1.1/sda1"
USE_1PASSWORD_SSH_AGENT=false
#############################################################################
RED="\033[1;91m"
GREEN="\033[1;92m"
YELLOW="\033[1;93m"
BLUE="\033[1;94m"
MAGENTA="\033[1;95m"
NC="\033[0m"
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
function refresh_dnf {
    sudo dnf clean all -y
    sudo dnf makecache -y
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
}
function refresh_flatpak {
    if command -v flatpak &> /dev/null; then
        log_info "Checking flatpak packages updates..."
        local output
        output=$(flatpak update --user -y 2>&1)
        if echo "$output" | grep -q "Updated"; then
            echo "$output"
        else
            log_success "Flatpak packages already up to date"
        fi
    fi
}
function refresh_and_upgrade {
    log_action "Refreshing DNF cache and upgrading system"
    refresh_dnf
    upgrade
    return 0
}
#############################################################################
#############################################################################
# SYSTEM
#############################################################################
#############################################################################
function system_add_sudoers {
    log_action "Adding $USER to sudoers file"
    if [ ! -f /etc/sudoers.d/"$USER" ]; then
        sudo /bin/su -c "cat <<EOF > /etc/sudoers.d/${USER}
${USER} ALL=(ALL:ALL) NOPASSWD: ALL
Defaults env_keep += \"SSH_AUTH_SOCK\"
EOF"
        if ! sudo visudo -c -f "/etc/sudoers.d/$USER"; then
            log_error "Sudoers file validation failed! Removing invalid file to prevent sudo lockout." 1>&2
            sudo rm -f "/etc/sudoers.d/$USER"
            return 1
        fi
        log_success "Sudoers file created and validated successfully"
    else
        log_info "Sudoers file already exists, skipping"
    fi
    return 0
}
#############################################################################
function system_create_ansible_dirs {
    log_action "Creating ansible dirs"
    sudo mkdir -p /root/.ansible/tmp
    sudo chmod 755 /root/.ansible/tmp
    sudo mkdir -p "$HOME/.ansible/tmp"
    sudo chmod 755 "$HOME/.ansible/tmp"
    return 0
}
#############################################################################
function system_limit_kernel_numbers {
    log_action "Edit /etc/dnf/dnf.conf to limit number of kernels to keep installed"
    ## This will automatically keep only 2 kernels (current + 1 backup) on future kernel updates
    if grep -q "^installonly_limit=" /etc/dnf/dnf.conf; then
        sudo sed -i 's/^installonly_limit=.*/installonly_limit=2/' /etc/dnf/dnf.conf
    else
        echo "installonly_limit=2" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
    fi
    return 0
}
#############################################################################
function system_enable_rpmfusion {
    log_action "ENABLING RPM Fusion repositories"
    sudo dnf config-manager setopt rpmfusion-nonfree-nvidia-driver.enabled=1
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        log_info "Installing RPM Fusion FREE repository..."
        sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
        log_success "RPM Fusion FREE installed"
    fi
    if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
        log_info "Installing RPM Fusion NONFREE repository..."
        sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
        log_success "RPM Fusion NONFREE installed"
    fi
    return 0
}
#############################################################################
#############################################################################
# REMOVING
#############################################################################
#############################################################################
function remove_apps {
    log_action "REMOVING Apps"
    local list_remove="kmahjongg, kmines, ksudoku, kpat, kpatience, ktorrent,
    konversation, kdeconnect, kwrite, kdeconnectd, kontact, kmail, kamoso,
    korganizer kaddressbook, elisa, lximage-qt, skanlite, neochat, dragon,
    skanpage, akregator, elisa-player, firefox, thunderbird,"
    for pkg in ${list_remove//,/ }; do
        log_info "Removing app: $pkg"
        sudo dnf remove -y "$pkg" 2>/dev/null || true
    done
    return 0
}
#############################################################################
function remove_libreoffice {
    log_action "REMOVING Libreoffice Apps"
    sudo dnf group remove -y libreoffice 2>/dev/null || true
    sudo dnf remove -y "libreoffice*" 2>/dev/null || true
    local list_remove_office="libreoffice, libreoffice-core, libreoffice-calc,
    libreoffice-base, libreoffice-draw, libreoffice-impress, libreoffice-writer,
    libreoffice-math"
    for pkg in ${list_remove_office//,/ }; do
        log_info "Removing: $pkg"
        sudo dnf remove -y "$pkg" 2>/dev/null || true
    done
    return 0
}
#############################################################################
#############################################################################
# INSTALLATIONS
#############################################################################
#############################################################################
function install_apps_gui {
    log_action "INSTALLING Apps (gui)"
    ## disabled: firefox, thunderbird, rpi-imager, gimp
    local list_apps_gui="kate, vlc, kleopatra, qbittorrent, piper, spectacle, obs, kolourpaint, filelight, guvcview,
    qt6-designer, plasma-firewall, texstudio, discord, filezilla, okular, kdenlive, gparted, kvantum, easyeffects,
    pdfarranger, ark"
    for pkg in ${list_apps_gui//,/ }; do
        log_info "INSTALLING app: $pkg"
        sudo dnf install -y "$pkg"
    done
    return 0
}
#############################################################################
function install_apps_cli {
    log_action "INSTALLING Apps (cli)"
    ## disabled: pipx, podman-compose
    ## python3-tkinter, python3-passlib, python3-bcrypt, python3-mysqlclient, mysql-connector-python3
    local list_apps_cli="curl, gh, git, git-filter-repo, git-extras, gcc-c++, valgrind, nmap, wget, vim,
    p7zip, p7zip-plugins, unrar, samba, gnupg2, kde-gtk-config, zstd, figlet, cowsay, cpupower, fd, btop,
    sshpass, sassc, golang, asciidoc, fastfetch"
    for pkg in ${list_apps_cli//,/ }; do
        log_info "INSTALLING app: $pkg"
        sudo dnf install -y "$pkg"
    done
    return 0
}
#############################################################################
function install_python_libs {
    log_action "INSTALLING Python Libs"
    local list_python_libs="python3-devel, python3-pip, python3-pyqt6, python3-tkinter, python3-openpyxl"
    for pkg in ${list_python_libs//,/ }; do
        log_info "Installing python lib: $pkg"
        sudo dnf install -y "$pkg"
    done
    return 0
}
#############################################################################
function install_libs {
    log_action "INSTALLING Libs"
    local list_libs="Cython, ntfs-3g, libffi-devel, sqlite, net-tools, hunspell-pt-BR,
    NetworkManager-openvpn, dnf-plugins-core, cmake, perl-Tk, cifs-utils, poppler-cpp-devel,
    libnotify, bzip2-devel, sqlite-devel, boost-devel, libpq-devel, mtools, dosfstools,
    python3-bcrypt, mysql-devel, screen, unixODBC-devel, libcurl-devel, zlib-devel, xz-devel,
    ncurses-devel, readline-devel, openssl, openssl-devel, gdbm-devel, tk-devel, usbutils,
    extra-cmake-modules, v4l-utils, dkms, libaio, libaio-devel, libudev-devel, libva, libva-utils,
    kernel-devel, kernel-headers, pass, ca-certificates, qt6-qtbase-devel, libusbmuxd-utils,
    pcsc-lite-devel, cabextract, libimobiledevice, libimobiledevice-utils, lm_sensors, libvirt-client,
    libusbmuxd-devel, ifuse, usbmuxd, wireguard-tools, kdecoration-devel, kf6-kcmutils-devel,
    kf6-ki18n-devel, kf6-kconfigwidgets-devel, kf6-kwindowsystem-devel, kf6-kguiaddons-devel,
    kf6-kiconthemes-devel, openldap-devel, cyrus-sasl-devel, kio-extras"
    for pkg in ${list_libs//,/ }; do
        log_info "Installing lib: $pkg"
        sudo dnf install -y "$pkg"
    done
    return 0
}
#############################################################################
function install_latex {
    log_action "INSTALLING Latex"
    ## all packages (3Gb): texlive-collection-latexextra
    local list_textlive="pandoc, texlive-latex, texlive-latex-fonts, texlive-moderncv, texlive-lastpage,
    texlive-enumitem, texlive-textpos, texlive-fontawesome5, texlive-multirow, texlive-arydshln,
    texlive-accsupp, texlive-tcolorbox, texlive-tikzfill, texlive-times, texlive-helvetic,
    texlive-courier, texlive-palatino"
    for pkg in ${list_textlive//,/ }; do
        log_info "Installing latex: $pkg"
        sudo dnf install -y "$pkg"
    done
    return 0
}
#############################################################################
function install_fonts {
    log_action "INSTALLING Fonts"
    local list_fonts="xorg-x11-font-utils, fontconfig"
    for pkg in ${list_fonts//,/ }; do
        log_info "Installing font: $pkg"
        sudo dnf install -y "$pkg"
    done
    return 0
}
#############################################################################
function install_nerd_fonts {
    log_action "INSTALLING Nerd Fonts"
    local nerd_font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
    local nerd_fonts_dir="$HOME/.fonts/nerd"
    local list_nerd_fonts="JetBrainsMono, FiraCode, Hack, Meslo, SourceCodePro, UbuntuMono,
    RobotoMono, CascadiaCode, Inconsolata, Noto, DejaVuSansMono, IBMPlexMono, LiberationMono,
    Iosevka, IosevkaTerm, VictorMono, Mononoki, AnonymousPro, FantasqueSansMono, SpaceMono,
    Monofur, Terminus, Go-Mono, IntelOneMono,"
    mkdir -p "$nerd_fonts_dir" 2>/dev/null || true
    for pkg in ${list_nerd_fonts//,/ }; do
        log_info "Installing nerd font: $pkg"
        rm -rf "${nerd_fonts_dir:?}/${pkg:?}"
        if wget -q "$nerd_font_url/$pkg.zip" -O "$nerd_fonts_dir/$pkg.zip"; then
            unzip -q "$nerd_fonts_dir/$pkg.zip" -d "$nerd_fonts_dir/$pkg"
            rm "$nerd_fonts_dir/$pkg.zip"
        else
            log_error "Failed to download nerd font: $pkg"
        fi
    done
    fc-cache -fr
    return 0
}
#############################################################################
function install_flatpak {
    log_action "INSTALLING Flatpak"
    log_info "Cleaning up old flatpak installation"
    flatpak remote-delete flathub --user 2>/dev/null || true
    flatpak remote-delete flathub --system 2>/dev/null || true
    #sudo rm -rf "$HOME/.local/share/flatpak"
    sudo dnf install -y flatpak
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    refresh_flatpak
    return 0
}
#############################################################################
function install_flatpak_apps {
    log_action "INSTALLING Flatpak apps"
    ## Application Data & Config: ~/.var/app
    ## Flatpak-specific directories: ~/.local/share/flatpak/app
    ## uninstall: flatpak uninstall --user --delete-data com.github.IsmaelMartinez.teams_for_linux
    local flatpak_apps="org.onlyoffice.desktopeditors, us.zoom.Zoom, eu.betterbird.Betterbird, com.spotify.Client"
    for pkg in ${flatpak_apps//,/ }; do
        log_info "Installing flatpak: $pkg"
        flatpak install --user -y flathub "$pkg"
    done

    #log_info "Configuring OBS Flatpak Apps permissions"
    #flatpak override --user --device=all com.obsproject.Studio
    #flatpak override --user --filesystem=/run/usbmuxd:ro com.obsproject.Studio

    return 0
}
#############################################################################
## gp-saml-gui
function install_uv_apps {
    log_action "INSTALLING UV apps for local user"
    local list_uv="nvibrant, aws-sso-util, awsume, cprofilev, black, ruff, poetry, pre-commit,
    ansible-core, pgcli, mycli"
    log_info "Cleaning up old UV installation"
    if command -v uv &> /dev/null; then
        for pkg in ${list_uv//,/ }; do
            uv tool uninstall "$pkg" 2>/dev/null || true
        done
    fi

    find "$HOME/.local/bin" -type l -lname "*/uv/tools/*" -delete 2>/dev/null || true
    sudo rm -rf "$HOME/.local/share/uv"
    sudo rm -ff "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
    curl --proto '=https' -LsSf https://astral.sh/uv/install.sh | sh

    for pkg in ${list_uv//,/ }; do
        log_info "Installing uv tool: $pkg"
        uv tool install "$pkg"
    done

    #sudo ln -sf "$HOME/.local/bin/black" /usr/bin/black
    #sudo ln -sf "$HOME/.local/bin/ruff" /usr/bin/ruff
    #sudo ln -sf "$HOME/.local/bin/poetry" /usr/bin/poetry

    echo
    log_info "Configuring Poetry virtualenvs to be inside projects"
    "$HOME/.local/bin/poetry" config virtualenvs.in-project true
    return 0
}
#############################################################################
#function install_pipx_apps {
#    log_action "INSTALLING Pipx apps for local user"
#    sudo dnf install -y pipx
#    local list_pipx="nvibrant, aws-sso-util, awsume, cprofilev, black, ruff, poetry"
#    for pkg in ${list_pipx//,/ }; do
#        echo -e "\n>>>>> INSTALLING pipx:" "$pkg"
#        pipx uninstall "$pkg"
#        pipx install "$pkg"
#    done
#    #sudo ln -sf "$HOME/.local/bin/black" /usr/bin/black
#    #sudo ln -sf "$HOME/.local/bin/ruff" /usr/bin/ruff
#    #sudo ln -sf "$HOME/.local/bin/poetry" /usr/bin/poetry
#    echo
#    log_info "Configuring Poetry virtualenvs to be inside projects"
#    "$HOME/.local/bin/poetry" config virtualenvs.in-project true
#    return 0
#}
#############################################################################
function install_yubikey_apps {
    log_action "INSTALLING YubiKey apps"
    local list_yubikey_apps=(
        "yubikey-manager"
        "yubikey-manager-qt"
        "yubico-piv-tool"
        "pam-u2f"
        "pamu2fcfg"
    )
    for pkg in "${list_yubikey_apps[@]}"; do
        log_info "INSTALLING YubiKey app: $pkg"
        sudo dnf install -y "$pkg"
    done

    ## Register the YubiKey
    mkdir -p "$HOME/.config/Yubico"
    if [[ ! -f "$HOME/.config/Yubico/u2f_keys" ]]; then
        log_info "Registering YubiKey - tap the key when it blinks"
        pamu2fcfg > "$HOME/.config/Yubico/u2f_keys"
        ## Uncomment below to register a backup key
        # log_info "Registering backup YubiKey - tap the backup key when it blinks"
        # pamu2fcfg -n >> "$HOME/.config/Yubico/u2f_keys"
    else
        log_info "YubiKey already registered, skipping"
    fi

    ## Configure polkit PAM for YubiKey touch authentication
    local polkit_pam="/etc/pam.d/polkit-1"
    local polkit_pam_lib="/usr/lib/pam.d/polkit-1"
    if [[ ! -f "$polkit_pam" ]] && [[ -f "$polkit_pam_lib" ]]; then
        log_info "Copying polkit PAM config to /etc/pam.d/"
        sudo cp "$polkit_pam_lib" "$polkit_pam"
    fi
    if ! grep -q "pam_u2f.so" "$polkit_pam" 2>/dev/null; then
        log_info "Configuring polkit PAM for YubiKey authentication"
        sudo sed -i '/^auth.*include.*system-auth/i auth  sufficient  pam_u2f.so cue' "$polkit_pam"
    else
        log_info "polkit PAM already configured for YubiKey, skipping"
    fi

    ## Configure sudo PAM for YubiKey touch authentication
    local sudo_pam="/etc/pam.d/sudo"
    local sudo_pam_lib="/usr/lib/pam.d/sudo"
    if [[ ! -f "$sudo_pam" ]] && [[ -f "$sudo_pam_lib" ]]; then
        log_info "Copying sudo PAM config to /etc/pam.d/"
        sudo cp "$sudo_pam_lib" "$sudo_pam"
    fi
    if ! grep -q "pam_u2f.so" "$sudo_pam" 2>/dev/null; then
        log_info "Configuring sudo PAM for YubiKey authentication"
        sudo sed -i '/^auth.*include.*system-auth\|^auth.*substack.*system-auth/i auth  sufficient  pam_u2f.so cue' "$sudo_pam"
    else
        log_info "sudo PAM already configured for YubiKey, skipping"
    fi

    return 0
}
#############################################################################
function install_docker {
    log_action "INSTALLING DOCKER"
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin 2>/dev/null || true
    sudo rm -f /etc/yum.repos.d/docker-ce.repo
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
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

    ## removes default -H fd:// flag that conflicts with "hosts" in daemon.json
    ## "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"],
    #sudo mkdir -p /etc/systemd/system/docker.service.d
    #sudo tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<'EOF'
#[Service]
#ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
#Environment=DOCKER_MIN_API_VERSION=1.24
#EOF

    sudo systemctl daemon-reload
    sudo systemctl unmask docker
    sudo systemctl enable docker
    sudo systemctl restart docker

    #sudo systemctl status docker
    #rpm -q docker-ce docker-ce-cli
    return 0
}
#############################################################################
function install_openlinkhub {
    log_action "INSTALLING OpenLinkHub"
    #sudo dnf copr enable -y jurkovic-nikola/OpenLinkHub fedora-43-x86_64
    sudo dnf copr enable -y jurkovic-nikola/OpenLinkHub
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
    log_success "Access OpenLinkHub at: http://localhost:27003"
    return 0
}
#############################################################################
function install_ollama {
    log_action "INSTALLING Ollama (local LLM inference)"
    local ollama_home="$HOME/Programs/ollama"
    local ollama_arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && ollama_arch="arm64"
    mkdir -p "$ollama_home"
    curl -fsSL "https://ollama.com/download/ollama-linux-${ollama_arch}.tar.zst" | tar --use-compress-program=unzstd -x -C "$ollama_home"
    ln -sf "$ollama_home/bin/ollama" "$HOME/bin/ollama"
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/ollama.service" << EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=$ollama_home/bin/ollama serve
Restart=always
RestartSec=3
Environment="PATH=$PATH"
Environment="OLLAMA_MODELS=$ollama_home/models"
Environment="OLLAMA_HOME=$ollama_home"

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable ollama
    systemctl --user start ollama

    # ollama pull qwen3-coder-next:latest
    # ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_AUTH_TOKEN=ollama claude --model Qwen3-Coder-Next:latest

    log_success "Ollama installed and service started"
    return 0
}
#############################################################################
function install_v4l2loopback {
    log_action "INSTALLING v4l2loopback for Virtual Camera (Zoom, Teams, Meet)"
    local sb_status
    sb_status=$(mokutil --sb-state 2>/dev/null || true)
    if echo "$sb_status" | grep -q "SecureBoot enabled"; then
        log_info "Secure Boot enabled - installing akmod-v4l2loopback (will be signed by akmods)"
        sudo dnf install -y akmod-v4l2loopback
        sudo akmods --force
    else
        log_info "Secure Boot disabled - installing v4l2loopback"
        sudo dnf install -y v4l2loopback
    fi
    ## Configure v4l2loopback to load at boot
    echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf > /dev/null
    ## Configure v4l2loopback module options (required for Chrome-based apps: Zoom, Teams, Meet)
    sudo tee /etc/modprobe.d/v4l2loopback.conf > /dev/null << 'EOF'
options v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1
EOF
    log_success "v4l2loopback installed (will be active after reboot)"
    return 0
}
#############################################################################
function install_msodbcsql18 {
    log_action "INSTALLING msodbcsql18"
    sudo dnf config-manager addrepo --overwrite --from-repofile=https://packages.microsoft.com/config/rhel/9/prod.repo
    sudo ACCEPT_EULA=Y dnf install -y --assumeyes msodbcsql18
    sudo ACCEPT_EULA=Y dnf install -y --assumeyes mssql-tools18
    sudo dnf install -y unixODBC-devel
    sudo dnf install -y unixODBC
    log_action "Excluding moby packages from Microsoft repository to prevent Docker CE conflicts"
    sudo sed -i '/repo_gpgcheck=1/a exclude=moby-cli moby-engine moby-buildx moby-compose' /etc/yum.repos.d/mssql-release.repo 2>/dev/null || true
    return 0
}
#############################################################################
function install_vs_code {
    log_action "INSTALLING VS Code"
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo 2>/dev/null || true
    dnf check-update
    sudo dnf install -y code # or code-insiders
    return 0
}
#############################################################################
function install_cursor_ai {
    log_action "INSTALLING Cursor AI"
    curl -fSL -o /tmp/cursor-ai.rpm "https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/2.6"
    sudo dnf install -y /tmp/cursor-ai.rpm
    rm -f /tmp/cursor-ai.rpm
    return 0
}
#############################################################################
function install_teams_for_linux {
    log_action "INSTALLING Teams for Linux"
    curl -1sLf -o /tmp/teams-for-linux.asc https://repo.teamsforlinux.de/teams-for-linux.asc && sudo rpm --import /tmp/teams-for-linux.asc
    sudo curl -1sLf -o /etc/yum.repos.d/teams-for-linux.repo https://repo.teamsforlinux.de/rpm/teams-for-linux.repo
    sudo dnf -y install teams-for-linux
    return 0
}
#############################################################################
function install_gp_saml_gui {
    log_action "INSTALLING gp-saml-gui"
    ## gp-saml-gui is a Python script used for interactive SAML authentication with GlobalProtect VPNs
    sudo dnf install -y python3-gobject gtk4-devel webkit2gtk4.1-devel wmctrl
    uv tool install https://github.com/dlenski/gp-saml-gui/archive/master.zip
    return 0
}
#############################################################################
function install_ffmpeg {
    log_action "INSTALLING ffmpeg (full version from RPM Fusion)"
    ## Replace ffmpeg-free with full ffmpeg from RPM Fusion for all codec support
    sudo dnf install -y ffmpeg ffmpeg-libs --allowerasing
    return 0
}
#############################################################################
function install_aws_cli {
    log_action "INSTALLING AWS cli"
    mkdir -p "$HOME/tmp" 2>/dev/null || true
    local _tmpdir="$HOME/tmp"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$_tmpdir/awscliv2.zip"
    unzip -o "$_tmpdir/awscliv2.zip" -d "$_tmpdir"
    rm -rf "$HOME/Programs/aws-cli"
    "$_tmpdir/aws/install" -i "$HOME/Programs/aws-cli" -b "$HOME/.local/bin"
    rm -rf "$_tmpdir/aws"*
    return 0
}
#############################################################################
function install_terraform {
    log_action "INSTALLING Terraform cli"
#    sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
#    sudo dnf install -y terraform
    curl -Lo /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.14.8/terraform_1.14.8_linux_amd64.zip
    sudo unzip -o /tmp/terraform.zip -d "$HOME/bin"
    rm -rf /tmp/terraform.zip "$HOME/bin/LICENSE.txt"
    return 0
}
#############################################################################
function install_bun {
    log_action "Installing Bun"
    curl -fsSL https://bun.sh/install | bash
    return 0
}
#############################################################################
function install_rust {
    log_action "Installing Rust"
    curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y
    #source "$HOME/.cargo/env"
    rustup update
    return 0
}
#############################################################################
function install_steam {
    log_action "Installing Steam"
    sudo dnf config-manager setopt rpmfusion-nonfree-steam.enabled=1
    sudo dnf install -y steam
    return 0
}
#############################################################################
function install_chrome {
    log_action "INSTALLING CHROME"
    sudo dnf config-manager setopt google-chrome.enabled=1
    sudo dnf install -y google-chrome-stable
    return 0
}
#############################################################################
function install_brave {
    log_action "INSTALLING Brave Browser Release Version"
    sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    sudo dnf install -y brave-browser
    return 0
}
#############################################################################
function install_librewolf {
    log_action "INSTALLING LibreWolf"
    sudo dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo
    sudo dnf install -y librewolf
    return 0
}
#############################################################################
function install_proton_pass {
    log_action "INSTALLING Proton Pass"
    # https://proton.me/pass/download/linux
    curl -fSL -o /tmp/ProtonPass.rpm "https://proton.me/download/pass/linux/proton-pass-1.35.0-1.x86_64.rpm" || { log_error "Download failed"; return 1; }
    sudo dnf install -y /tmp/ProtonPass.rpm || { log_error "Install failed"; return 1; }
    rm -f /tmp/ProtonPass.rpm
    log_success "Proton Pass installed successfully"
    return 0
}
#############################################################################
function install_proton_bridge {
    log_action "INSTALLING Proton Bridge"
    # https://proton.me/mail/bridge
    curl -fSL -o /tmp/protonmail-bridge.rpm "https://proton.me/download/bridge/protonmail-bridge-3.23.1-1.x86_64.rpm" || { log_error "Download failed"; return 1; }
    sudo dnf install -y /tmp/protonmail-bridge.rpm || { log_error "Install failed"; return 1; }
    rm -f /tmp/protonmail-bridge.rpm
    log_success "Proton Bridge installed successfully"
    return 0
}
#############################################################################
function install_1password {
    log_action "INSTALLING 1PASSWORD"
    sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
    sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
    #sudo sh -c 'echo -e "[1password]\nname=1Password Edge Channel\nbaseurl=https://downloads.1password.com/linux/rpm/edge/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc" > /etc/yum.repos.d/1password.repo'
    sudo dnf check-update -y 1password 1password-cli && sudo dnf install -y 1password 1password-cli

    if [ "$USE_1PASSWORD_SSH_AGENT" = "true" ]; then
        log_action "Configuring 1Password SSH agent"

        # Verify 1Password is installed
        if ! command -v 1password &> /dev/null; then
            log_warn "1Password not found - install it first before using SSH agent"
            return 1
        fi

        # Disable systemd SSH agent
        log_info "Disabling systemd SSH agent"
        systemctl --user stop ssh-agent.service 2>/dev/null || true
        systemctl --user disable ssh-agent.service 2>/dev/null || true
        systemctl --user mask ssh-agent.service 2>/dev/null || true
        systemctl --user stop ssh-agent.socket 2>/dev/null || true
        systemctl --user disable ssh-agent.socket 2>/dev/null || true
        systemctl --user mask ssh-agent.socket 2>/dev/null || true

        # Configure shell to use 1Password SSH agent
        log_info "Configuring shell to use 1Password SSH agent"
        if [ -f "$HOME/.shellrc" ]; then
            # Check if SSH_AUTH_SOCK is already configured for 1Password
            if ! grep -q "SSH_AUTH_SOCK.*1password.*agent.sock" "$HOME/.shellrc"; then
                # Add 1Password SSH agent configuration
                sed -i '/^#* *1Password SSH Agent/,/^export SSH_AUTH_SOCK/d' "$HOME/.shellrc" 2>/dev/null || true
                # shellcheck disable=SC2016
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

        # Configure systemd user environment
        log_info "Configuring systemd user environment for 1Password SSH agent"
        mkdir -p "$HOME/.config/environment.d"
        if ! grep -q 'SSH_AUTH_SOCK="/home/.*/\.1password/agent\.sock"' "$HOME/.config/environment.d/environment.conf" 2>/dev/null; then
            echo "SSH_AUTH_SOCK=\"$HOME/.1password/agent.sock\"" >> "$HOME/.config/environment.d/environment.conf"
            log_success "Added SSH_AUTH_SOCK to environment.d"
        else
            log_info "SSH_AUTH_SOCK already configured in environment.d"
        fi

        # Configure KDE Plasma to use 1Password SSH agent
        log_info "Configuring KDE Plasma environment for 1Password SSH agent"
        mkdir -p "$HOME/.config/plasma-workspace/env"
        cat > "$HOME/.config/plasma-workspace/env/ssh-agent.sh" << EOFPLASMA
#!/bin/sh
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
EOFPLASMA
        chmod +x "$HOME/.config/plasma-workspace/env/ssh-agent.sh"
        log_success "Created KDE Plasma SSH agent configuration"

        # Set immediately for current session
        systemctl --user set-environment SSH_AUTH_SOCK="$HOME/.1password/agent.sock" 2>/dev/null || true

        # linking to default location
        ln -sf "$HOME/.1password/agent.sock" /run/user/1000/ssh-agent.socket

        log_success "1Password SSH agent configured"
    else
        log_info "1Password SSH agent disabled (USE_1PASSWORD_SSH_AGENT=false)"
    fi

    return 0
}
#############################################################################
#function install_rpmfusion_virtualbox {
#    log_action "INSTALLING virtualbox from rpmfusion WITHOUT SECURE BOOT"
#    sudo dnf install -y virtualbox virtualbox-guest-additions
#    sudo usermod -a -G vboxusers "${USER}"
#    sudo systemctl enable vboxdrv
#    sudo systemctl restart vboxdrv
#    return 0
#}
#############################################################################
function install_qemu_kvm {
    log_action "INSTALLING Qemu/KVM Virtual Machine Manager"
    sudo dnf install -y virt-manager
    ## disabling STP
    sudo virsh net-dumpxml default | sed "s/stp='on'/stp='off'/" | sudo virsh net-define /dev/stdin
    sudo virsh net-destroy default && sudo virsh net-start default
    # sudo virsh net-dumpxml default | grep bridge
    echo "Adding ${USER} user to kvm"
    sudo modprobe kvm
    sudo modprobe kvm_intel
    sudo usermod -aG kvm "${USER}"
    sudo usermod -aG libvirt "${USER}"
    return 0
}
#############################################################################
function install_teamviewer {
    log_action "DOWNLOADING TEAMVIEWER"
    sudo dnf install -y https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm
    return 0
}
#############################################################################
function install_globalprotect_openconnect {
    log_action "INSTALLING globalprotect-openconnect"
    sudo dnf copr enable -y yuezk/globalprotect-openconnect
    sudo dnf install -y globalprotect-openconnect
    return 0
}
#############################################################################
function install_ddcutil {
    log_action "INSTALLING ddcutil"
    sudo dnf copr enable -y rockowitz/ddcutil
    sudo dnf install -y qt6-qtbase-devel qt6-qttools-devel qt6-linguist
    sudo dnf install -y ddcutil ddcutil-devel glib2-devel pkgconfig cmake gcc-c++
    mkdir build && cd build
    cmake -DUSE_QT6=ON -DCMAKE_INSTALL_PREFIX="$HOME/Programs/ddcui"
    cmake --build . -j"$(nproc)"
    cmake --install .
    return 0
}
#############################################################################
function install_droidcam_client {
    log_action "INSTALLING DroidCam client (use iPhone/Android as webcam)"
    wget -O /tmp/droidcam-client.rpm https://droidcam.app/go/droidCam.client.setup.rpm
    sudo dnf install -y /tmp/droidcam-client.rpm
    rm -f /tmp/droidcam-client.rpm
    return 0
}
#############################################################################
function install_coolercontrol {
    log_action "INSTALLING CoolerControl"
    sudo dnf copr enable -y codifryed/CoolerControl
    sudo dnf install -y coolercontrol
    sudo chmod a+r /dev/port
    sudo mkdir -p /etc/modules-load.d
    sudo tee /etc/modules-load.d/nct6775.conf > /dev/null <<EOF
nct6775
EOF
    yes | sudo sensors-detect --auto
    sudo systemctl enable --now coolercontrold

    ## Set pwmconfig (yes for all and then 9(save and quit))
    #sudo cp /usr/bin/pwmconfig /usr/bin/pwmconfig.bak
    #sudo sed -i 's/egrep/grep -E/g' /usr/bin/pwmconfig
    #sudo pwmconfig

    ## If you need to manually load/unload it:
    #sudo modprobe nct6775      # load
    #sudo modprobe -r nct6775   # unload

    return 0
}
#############################################################################
#############################################################################
# CONFIGURATIONS
#############################################################################
#############################################################################
function configure_auto_login {
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
    return 0
}
#############################################################################
function configure_fstab_mounts {
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

#    sudo mkdir -p /run/media/ddc/{Users,Games,Windows}
#    sudo tee /etc/fstab > /dev/null << 'EOF'
#UUID=6652C5F152C5C5D1 /run/media/ddc/Users   ntfs-3g rw,uid=1000,gid=1000,windows_names,nofail 0 0
#UUID=461E22781E2260E3 /run/media/ddc/Games   ntfs-3g rw,uid=1000,gid=1000,windows_names,nofail 0 0
#UUID=50C28318C2830208 /run/media/ddc/Windows ntfs-3g rw,uid=1000,gid=1000,windows_names,nofail 0 0
#EOF

    sudo tee /etc/udisks2/mount_options.conf > /dev/null << 'EOF'
[defaults]
ntfs_defaults=uid=$UID,gid=$GID,windows_names,rw
ntfs:ntfs_defaults=uid=$UID,gid=$GID,windows_names,rw
ntfs_drivers=ntfs-3g,ntfs3
EOF

    sudo chmod u+s /usr/bin/mount.cifs
    sudo systemctl daemon-reload
    sudo mount -a 2>/dev/null || true
    return 0
}
#############################################################################
function configure_grub_modifications {
    ### GRUB_CMDLINE_LINUX="rhgb quiet rd.driver.blacklist=nouveau,nova_core modprobe.blacklist=nouveau,nova_core intel_pstate=passive"
    log_action "Starting GRUB modifications"
    log_info "GRUB - Disable memtest/uefi entries"
    sudo chmod 644 /etc/grub.d/20_memtest86+ 2>/dev/null || true
    sudo chmod 644 /etc/grub.d/30_uefi-firmware 2>/dev/null || true
    #####
#    log_info "GRUB - Changing timeout and screen resolution"
#    if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
#        sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/" /etc/default/grub
#    else
#        echo "GRUB_TIMEOUT=5" | sudo tee -a /etc/default/grub > /dev/null
#    fi
#    if ! grep -q "^GRUB_RECORDFAIL_TIMEOUT" /etc/default/grub; then
#        echo "GRUB_RECORDFAIL_TIMEOUT=5" | sudo tee -a /etc/default/grub > /dev/null
#    fi
#    if ! grep -q "^GRUB_GFXPAYLOAD_LINUX" /etc/default/grub; then
#        echo "GRUB_GFXPAYLOAD_LINUX=keep" | sudo tee -a /etc/default/grub > /dev/null
#    fi
#    if ! grep -q "^GRUB_GFXMODE" /etc/default/grub; then
#        echo "GRUB_GFXMODE=1920x1080" | sudo tee -a /etc/default/grub > /dev/null
#    fi
    #####
#     log_info "GRUB - Installing Theme"
#     mkdir -p "$HOME/tmp" 2>/dev/null || true
#     local _tmpdir="$HOME/tmp"
#     git clone --depth=1 https://github.com/vinceliuice/grub2-themes.git "$_tmpdir/grub2-themes"
#     sudo "$_tmpdir/grub2-themes/install.sh" -t stylish -s 1080p
#     sudo cp "$SCRIPT_DIR/assets/grub_background.jpg" /usr/share/grub/themes/stylish/background.jpg
#     rm -rf "$_tmpdir/grub2-themes"
#     #####
#     SB_STATUS=$(mokutil --sb-state 2>/dev/null || true)
#     if echo "$SB_STATUS" | grep -q "SecureBoot enabled"; then
#         log_info "GRUB - Commenting out GRUB_FONT settings since secure boot is enabled"
#         sudo sed -i 's/^GRUB_FONT=/#GRUB_FONT=/' /etc/default/grub
#     fi
    #####
    log_info "GRUB - Updating grub configuration"
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    return 0
}
#############################################################################
function configure_cpu_frequency {
    log_action "Changing cpu frequency"
    sudo systemctl enable cpupower
    sudo cpupower frequency-set -g performance
    sudo cpupower frequency-set --max 5.6ghz
    sudo cpupower frequency-set --min 5.6ghz
    sudo systemctl start cpupower
    grep -i mhz /proc/cpuinfo
    return 0
}
#############################################################################
function configure_rtc_localtime {
    log_action "Set RTC time to use local time to fix windows clock"
    sudo timedatectl set-local-rtc 1 --adjust-system-clock
    return 0
}
#############################################################################
function configure_firewalls {
    log_action "Enabling firewalls" ## docker and podman ips
    sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" source address="172.0.0.0/8" accept'
    sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" destination address="172.0.0.0/8" accept'
    sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" source address="10.88.0.0/16" accept'
    sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-rich-rule='rule family="ipv4" destination address="10.88.0.0/16" accept'
    sudo firewall-cmd --reload
    ## sudo firewall-cmd --zone=FedoraWorkstation --list-rich-rules
    return 0
}
#############################################################################
function configure_chrome_sandbox_perms {
    log_action "Fixing chrome sandbox perms"
    sudo chown root:ddc "$HOME/Programs/Jetbrains/Clion/jbr/lib/chrome-sandbox" 2>/dev/null || true
    sudo chmod 4755 "$HOME/Programs/Jetbrains/Clion/jbr/lib/chrome-sandbox" 2>/dev/null || true

    sudo chown root:ddc "$HOME/Programs/Jetbrains/DataGrip/jbr/lib/chrome-sandbox" 2>/dev/null || true
    sudo chmod 4755 "$HOME/Programs/Jetbrains/DataGrip/jbr/lib/chrome-sandbox" 2>/dev/null || true

    sudo chown root:ddc "$HOME/Programs/Jetbrains/Pycharm/jbr/lib/chrome-sandbox" 2>/dev/null || true
    sudo chmod 4755 "$HOME/Programs/Jetbrains/Pycharm/jbr/lib/chrome-sandbox" 2>/dev/null || true
    return 0
}
#############################################################################
function configure_podman_docker_hub {
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
    return 0
}
#############################################################################
function configure_sysctl_config {
    log_action "Set /etc/sysctl.d/60-custom.conf"
    sudo tee /etc/sysctl.d/60-custom.conf > /dev/null << 'EOF'
## Set inotify watch limit high enough
fs.inotify.max_user_instances = 16384
fs.inotify.max_user_watches = 1048576

## Wi-Fi Optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 262144
net.core.wmem_default = 262144

net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_mem = 786432 1048576 1572864

## Wi-Fi Specific Optimizations
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fastopen = 3

## Set Yama security to restricted
kernel.yama.ptrace_scope = 1
EOF
    sudo sysctl -p /etc/sysctl.d/60-custom.conf
    return 0
}
#############################################################################
function configure_pam_limits {
    log_action "Set PAM limits"
    ## System limits
    sudo tee /etc/security/limits.d/99-global-highperf.conf > /dev/null << 'EOF'
# Global high performance limits - for ALL users including system daemons
* soft nofile 524288
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
* soft nproc 65536
* hard nproc 65536
EOF

    sudo mkdir -p /etc/systemd/system.conf.d
    sudo tee /etc/systemd/system.conf.d/limits.conf > /dev/null << 'EOF'
[Manager]
DefaultLimitNOFILE=524288:1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitNPROC=65536:65536
EOF

    sudo mkdir -p /etc/systemd/user.conf.d
    sudo tee /etc/systemd/user.conf.d/limits.conf > /dev/null << 'EOF'
[Manager]
DefaultLimitNOFILE=524288:1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitNPROC=65536:65536
EOF

    ## ulimit -n  # Should show 524288
    ## ulimit -l  # Should show unlimited
    ## ulimit -Hn
    ## sudo grep -r "Max open files" /proc/*/limits 2>/dev/null | head -20
    return 0
}
#############################################################################
function configure_prefer_ipv4 {
    log_action "Prefer IPv4 over IPv6"
    ## Create a /etc/gai.conf file to prefer IPv4 for dual-stack systems.
    ## This keeps IPv6 enabled but makes the system prefer IPv4 when both are available
    sudo tee /etc/gai.conf > /dev/null << 'EOF'
## Prefer IPv4 over IPv6
precedence ::ffff:0:0/96  100
EOF
    return 0
}
#############################################################################
function configure_set_locales {
    log_action "Set locales"
    sudo localectl set-locale LANG=en_US.UTF-8
    return 0
}
#############################################################################
function configure_fix_gnupg_perms {
    log_action "Fix gnupg directory permissions"
    chown -R "$USER" "$HOME/.gnupg" 2>/dev/null || true
    chmod -R 700 "$HOME/.gnupg" 2>/dev/null || true
    return 0
}
#############################################################################
function configure_fix_ssh_perms {
    log_action "Fix ssh config file permissions"
    chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
    return 0
}
#############################################################################
function configure_set_hostname {
    log_action "Set hostname to ddcx"
    sudo hostnamectl set-hostname ddcx
    sudo systemctl restart systemd-hostnamed
    return 0
}
#############################################################################
function configure_disable_pip_keyring {
    log_action "Disabling pip kwallet/keyring"
    python -m keyring --disable 2>/dev/null || true
    sudo python -m keyring --disable 2>/dev/null || true
    return 0
}
#############################################################################
function configure_oracle_client {
    log_action "Load Oracle instant client"
    sudo sh -c "echo $HOME/Programs/oracle > /etc/ld.so.conf.d/oracle-instantclient.conf"
    sudo ldconfig
    return 0
}
#############################################################################
function configure_disable_nm_wait_online {
    log_action "Disable NetworkManager-wait-online (Saves ~5.5s on boot time)"
    sudo systemctl disable NetworkManager-wait-online.service
    return 0
}
#############################################################################
function configure_wifi_tuning {
    log_action "WiFi tuning - Disable power saving for stable connections"
    sudo mkdir -p /etc/NetworkManager/conf.d
    sudo tee /etc/NetworkManager/conf.d/wifi-tuning.conf > /dev/null << 'EOF'
[connection-wifi]
wifi.powersave=0
EOF
    sudo nmcli general reload
    sudo tee /etc/modprobe.d/iwlwifi.conf > /dev/null << 'EOF'
options iwlwifi power_save=0 uapsd_disable=1
EOF
    return 0
}
#############################################################################
function configure_disable_wifi_mac_randomization {
    log_action "Disabling WiFi MAC address randomization for static IP reliability"
    ## Override Fedora default (stable-ssid) to use permanent hardware MAC
    sudo tee /etc/NetworkManager/conf.d/22-wifi-mac-addr.conf > /dev/null << 'EOF'
[connection.22-wifi-mac-addr]
wifi.cloned-mac-address=permanent
EOF
    sudo nmcli general reload
    return 0
}
#############################################################################
function configure_check_swap {
    log_action "Checking swap configuration"
    if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -gt 60000000 ]; then
        log_info "System has >60GB RAM, disabling swap for performance"
        sudo swapoff -a
    else
        log_info "System has <60GB RAM, keeping swap enabled"
    fi
    return 0
}
#############################################################################
function configure_zsh_user {
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
    return 0
}
#############################################################################
function configure_zsh_root {
    log_action "Changing default root shell from bash to zsh"
    sudo usermod -s "$(which zsh)" root
    log_info "Copying zsh files to root user"
    sudo cp -R "$HOME/.oh-my-zsh" /root
    sudo cp "$HOME/.oh-my-zsh.zsh" /root
    sudo cp "$HOME/.zshrc" /root
    sudo cp "$HOME/.p10k.zsh" /root
    sudo cp "$HOME/.shellrc" /root
    sudo cp "$HOME/.vimrc" /root
    sudo cp "$HOME/.bashrc" /root
    return 0
}
#############################################################################
function configure_refresh_kde_menu {
    log_action "Refreshing KDE menu and desktop database"
    log_info "This ensures custom applications appear correctly after reinstall"
    log_warn "DO NOT click 'Edit -> Restore to system menu' in kmenuedit - it will delete all custom apps!"
    kbuildsycoca6 --noincremental 2>/dev/null || log_warn "kbuildsycoca6 not found, skipping KDE cache rebuild"
    update-desktop-database ~/.local/share/applications/ 2>/dev/null || log_warn "update-desktop-database failed, skipping"
    gtk-update-icon-cache -f ~/.local/share/icons/ 2>/dev/null || log_info "Icon cache update skipped (directory may not exist)"
    log_success "KDE menu refresh completed"
    return 0
}
#############################################################################
#log_action "Configure SELinux (optional - set to permissive for development)"
# sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
#############################################################################
# log_action "Fixing firefox SELinux"
# mkdir -p "$HOME/.mozilla/firefox/*/gmp-widevinecdm" 2>/dev/null || true
# sudo restorecon -R "$HOME/.mozilla/firefox" 2>/dev/null || true
#############################################################################
function configure_reload_systemd {
    # After reboot, run: systemd-analyze
    log_action "Reloading systemd..."
    sudo systemctl daemon-reload
    return 0
}
#############################################################################
#############################################################################
# CLI MODE - runs all functions sequentially when executed directly
#############################################################################
#############################################################################
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e          # Exit on error
    set -u          # Error on undefined variables
    set -o pipefail # Pipe failures propagate

    [[ $EUID -eq 0 ]] && log_error "Script cannot be run by root" && exit 1

    mkdir -p "$HOME/Programs" 2>/dev/null || true
    mkdir -p "$HOME/tmp" 2>/dev/null || true

    ALL_FUNCTIONS=(
        system_add_sudoers
        system_create_ansible_dirs
        system_limit_kernel_numbers
        system_enable_rpmfusion

        remove_apps
        remove_libreoffice
        refresh_dnf

        install_apps_gui
        install_apps_cli
        install_python_libs
        install_libs
        install_latex
        install_fonts
        install_nerd_fonts
        install_flatpak
        install_flatpak_apps
        install_uv_apps
        #install_pipx_apps
        install_yubikey_apps
        install_docker
        install_openlinkhub
        #install_ollama
        install_v4l2loopback
        install_msodbcsql18
        #install_vs_code
        #install_cursor_ai
        install_teams_for_linux
        install_gp_saml_gui
        install_ffmpeg
        install_aws_cli
        install_terraform
        install_bun
        install_rust
        #install_steam
        install_chrome
        install_brave
        install_librewolf
        install_1password
        install_proton_pass
        install_proton_bridge
        #install_rpmfusion_virtualbox
        #install_qemu_kvm
        #install_teamviewer
        install_globalprotect_openconnect
        #install_ddcutil
        #install_droidcam_client
        install_coolercontrol

        configure_auto_login
        configure_fstab_mounts
        configure_grub_modifications
        configure_cpu_frequency
        configure_rtc_localtime
        configure_firewalls
        configure_chrome_sandbox_perms
        configure_podman_docker_hub
        configure_sysctl_config
        configure_pam_limits
        configure_prefer_ipv4
        configure_set_locales
        configure_fix_gnupg_perms
        configure_fix_ssh_perms
        configure_set_hostname
        configure_disable_pip_keyring
        configure_oracle_client
        configure_disable_nm_wait_online
        configure_wifi_tuning
        configure_disable_wifi_mac_randomization
        configure_check_swap
        configure_zsh_user
        configure_zsh_root
        configure_refresh_kde_menu
        configure_reload_systemd

        refresh_and_upgrade
    )

    for fn in "${ALL_FUNCTIONS[@]}"; do
        "$fn"
    done

    echo
    log_success "INSTALLATION COMPLETED!"
    echo
    log_warn "REBOOTING IN 10 SECONDS TO APPLY ALL CHANGES..."
    sleep 10 && sudo reboot
fi

#############################################################################
#############################################################################
## NOTES
#############################################################################
#############################################################################
## DNF Repos
## list:       dnf repolist --all
## enable:     sudo dnf config-manager setopt rpmfusion-nonfree-steam.enabled=1
## add:        sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
## remove:     sudo rm /etc/yum.repos.d/brave-browser.repo
#############################################################################
## Remove COPR repos
## sudo dnf copr remove -y rockowitz/ddcutil
#############################################################################
## Remove flatpak repos
## uninstall: flatpak uninstall --user --delete-data eu.betterbird.Betterbird
#############################################################################
## KATE Python syntax highlighting
## Settings -> Configure Kate... -> Open/Save -> Modes & Filetypes -> Filetype: Normal -> "Variables:" ->  kate: syntax Python;
#############################################################################
## IBUS Problem
## The problem is that with the "Ibus" input method, "Ctrl-shift-u" is by default configured to the "Unicode Code Point" shortcut.
## You can try this: Type ctrl-shift-u, then an (underlined) u appears.
## If you then type a unicode code point number in hex (e.g. 21, the ASCII/unicode CP for !) and press enter, it is replaced with the corresponding character.
##
## Example of ctr-shift-u
##
## Solution
## This shortcut can be changed or disabled using the ibus-setup utility:
## Run ibus-setup from the terminal (or open IBus Preferences).
## Go to "Emoji".
## Next to "Unicode code point:", click on the three dots (i.e. ...).
## In the dialog, click "Delete", then "OK".
## Close the IBus Preferences window.
#############################################################################
