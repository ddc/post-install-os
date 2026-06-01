# Fedora Post-Installation Scripts

Scripts for setting up a fresh Fedora installation with NVIDIA drivers, Secure Boot (MOK), and essential applications.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation Order](#installation-order)
- [Scripts Overview](#scripts-overview)
  - [1. NVIDIA Installation](#1-nvidia-installation)
  - [2. NVIDIA Verification](#2-nvidia-verification)
  - [3. Main Installation Script](#3-main-installation-script)
  - [4. VirtualBox Installation](#4-virtualbox-installation)
- [MOK (Machine Owner Key) Enrollment](#mok-machine-owner-key-enrollment)
- [What Gets Installed](#what-gets-installed)
- [Secure Boot and Kernel Modules](#secure-boot-and-kernel-modules)
- [Troubleshooting](#troubleshooting)
- [Uninstallation](#uninstallation)

---

## Prerequisites

- Fresh Fedora installation (tested on Fedora 43)
- Secure Boot enabled in BIOS/UEFI
- NVIDIA GPU (for nvidia script)
- Internet connection

---

## Installation Order

Run the scripts in this order on a fresh Fedora install:

```
Step 1: NVIDIA + MOK Setup
─────────────────────────────────────────────────────
$ sudo ./1_apps/1_nvidia_install_fedora_secureboot_mok.sh

    ↓ Sets up:
    • RPM Fusion repositories
    • NVIDIA drivers (akmod-nvidia)
    • akmods signing infrastructure
    • Generates MOK signing key (kmodgenca -a)
    • Schedules MOK enrollment

─────────────────────────────────────────────────────
Step 2: REBOOT + MOK Enrollment
─────────────────────────────────────────────────────
$ sudo reboot

    ↓ At the BLUE MOK screen:
    • Press any key when prompted
    • Select: "Enroll MOK"
    • Select: "Continue"
    • Enter your password
    • Select: "Yes"
    • System reboots automatically

─────────────────────────────────────────────────────
Step 3: Verify NVIDIA Installation (Optional)
─────────────────────────────────────────────────────
$ ./1_apps/2_verify_nvidia_installation_secureboot_mok.sh

    ↓ Verifies:
    • MOK key enrollment
    • NVIDIA module is loaded and signed
    • GPU is detected

─────────────────────────────────────────────────────
Step 4: Main Installation Script
─────────────────────────────────────────────────────
$ ./1_apps/3_first_install_fedora_after_nvidia.sh

    ↓ Installs:
    • All applications, libraries, fonts
    • Flatpak apps (Spotify, Zoom, Teams, etc.)
    • Docker, AWS CLI, browsers
    • v4l2loopback (OBS Virtual Camera)
    • System configurations
    • Auto-reboots when complete

─────────────────────────────────────────────────────
Step 5: VirtualBox (Optional)
─────────────────────────────────────────────────────
$ sudo ./2_virtualbox/1_install_virtualbox_secureboot_mok.sh
$ sudo reboot
$ ./2_virtualbox/2_verification_virtualbox_secureboot_mok.sh
```

---

## Scripts Overview

### 1. NVIDIA Installation

**Script:** `1_apps/1_nvidia_install_fedora_secureboot_mok.sh`

**Run as:** `sudo`

Installs NVIDIA drivers with Secure Boot support using MOK (Machine Owner Key).

**What it does:**
- Enables RPM Fusion repositories (free and nonfree)
- Installs NVIDIA packages:
  - `akmod-nvidia` - NVIDIA kernel module (auto-rebuilds on kernel updates)
  - `xorg-x11-drv-nvidia-cuda` - CUDA support
  - `libva-nvidia-driver` - VA-API hardware acceleration
  - `vulkan` - Vulkan support
- Sets up akmods signing infrastructure
- Generates MOK signing key (`kmodgenca -a`)
- Schedules key enrollment via `mokutil --import`

### 2. NVIDIA Verification

**Script:** `1_apps/2_verify_nvidia_installation_secureboot_mok.sh`

**Run as:** normal user

Verifies that NVIDIA drivers are properly installed and working with Secure Boot.

**Checks:**
- Secure Boot status
- MOK key enrollment status
- NVIDIA kernel module signature
- GPU detection (`nvidia-smi`)
- VA-API status

### 3. Main Installation Script

**Script:** `1_apps/3_first_install_fedora_after_nvidia.sh`

**Run as:** normal user (uses sudo internally)

**Important:** Run this AFTER the NVIDIA script and MOK enrollment.

Main system setup script that installs applications and configures the system.

### 4. VirtualBox Installation

**Script:** `2_virtualbox/1_install_virtualbox_secureboot_mok.sh`

**Run as:** `sudo`

Installs VirtualBox with Secure Boot support. Uses the same akmods signing key as NVIDIA.

---

## MOK (Machine Owner Key) Enrollment

MOK enrollment is required for Secure Boot to trust kernel modules signed by akmods.

**The akmods key signs ALL akmod modules:**
```
/etc/pki/akmods/certs/public_key.der  ← Enrolled in MOK (trusted by Secure Boot)
/etc/pki/akmods/private/private_key.priv ← Signs kernel modules

        akmods key
            │
            ├── signs → akmod-nvidia
            ├── signs → akmod-v4l2loopback
            └── signs → akmod-VirtualBox
```

**MOK enrollment happens once** - after that, all modules signed with the same key are trusted.

### MOK Screen Steps

When you reboot after running the NVIDIA script:

1. A **BLUE MOK screen** appears
2. Press **any key** when prompted (you have ~10 seconds)
3. Select **"Enroll MOK"**
4. Select **"Continue"**
5. Enter the **password you set** during installation
6. Select **"Yes"** to confirm
7. System reboots automatically

**If you miss the MOK screen:** The key enrollment is still pending. Just reboot again.

---

## What Gets Installed

### Applications
| Category    | Packages                              |
|-------------|---------------------------------------|
| Development | git, gcc-c++, golang, cmake, valgrind |
| Editors     | vim, kate                             |
| Media       | vlc, obs-studio, gimp, kdenlive       |
| Utilities   | btop, fastfetch, gparted, filelight   |
| Networking  | nmap, filezilla, sshpass              |

### Browsers
- Google Chrome
- Brave Browser
- LibreWolf

### Flatpak Apps
- Spotify
- Zoom
- Microsoft Teams
- OnlyOffice

### System Tools
- Docker CE
- AWS CLI
- 1Password
- OpenLinkHub (Corsair device control)

### OBS Virtual Camera (v4l2loopback)

For using OBS output in video calls (Zoom, Teams, Google Meet):

- **DroidCam OBS plugin** - Use iPhone/Android as camera in OBS
- **v4l2loopback** - Virtual camera device for OBS → other apps
- **usbmuxd** - Required for iPhone USB connection

---

## Secure Boot and Kernel Modules

### How Signing Works

```
1. kmodgenca -a        → Creates signing key pair
2. akmods --force      → Builds module + signs with key
3. mokutil --import    → Enrolls public key in MOK
4. [Reboot + MOK]      → Key trusted by Secure Boot
5. Module loads        → Signature verified, module allowed
```

### Supported Signed Modules

| Module       | Package            | Purpose            |
|--------------|--------------------|--------------------|
| nvidia       | akmod-nvidia       | NVIDIA GPU driver  |
| v4l2loopback | akmod-v4l2loopback | OBS Virtual Camera |
| vboxdrv      | akmod-VirtualBox   | VirtualBox         |

---

## Troubleshooting

### NVIDIA module not loading

```bash
# Check if module is signed
modinfo -F signer nvidia

# Check MOK enrollment
mokutil --list-enrolled | grep akmods

# Rebuild module
sudo akmods --force
```

### v4l2loopback not working

```bash
# Check if module is loaded
lsmod | grep v4l2loopback

# Load manually
sudo modprobe v4l2loopback

# Check for errors
dmesg | grep v4l2
```

### MOK enrollment not working

```bash
# Check pending enrollments
mokutil --list-new

# Re-import key
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

### Secure Boot status

```bash
mokutil --sb-state
```

---

## Uninstallation

### NVIDIA

```bash
sudo ./1_apps/uninstall_nvidia_secureboot_mok.sh
```

### VirtualBox

```bash
sudo ./2_virtualbox/uninstall_virtualbox_secureboot_mok.sh
```

---

## Directory Structure

```
fedora/
├── README.md
├── 1_apps/
│   ├── 1_nvidia_install_fedora_secureboot_mok.sh
│   ├── 2_verify_nvidia_installation_secureboot_mok.sh
│   ├── 3_first_install_fedora_after_nvidia.sh
│   └── uninstall_nvidia_secureboot_mok.sh
├── 2_virtualbox/
│   ├── 1_install_virtualbox_secureboot_mok.sh
│   ├── 2_verification_virtualbox_secureboot_mok.sh
│   └── uninstall_virtualbox_secureboot_mok.sh
└── others/
    ├── scripts/
    ├── 3_custom_kernels/
    ├── 4_safing_portmaster/
    └── vmware/
```
