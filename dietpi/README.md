# DietPi Ansible Playbook

Automated configuration for DietPi (Raspberry Pi) using Ansible.

## Prerequisites

- DietPi installed on Raspberry Pi
- SSH access to the Pi
- Ansible installed on your control machine

## Quick Start

```bash
cd dietpi/ansible

# Test connection first
ansible -i inventory.yml raspberrypi -m ping -k

# Run entire playbook (initial setup)
ansible-playbook -i inventory.yml playbook.yml -k

# Run entire playbook and clean deploy specific containers (wipes data, volumes, networks)
ansible-playbook -i inventory.yml playbook.yml -e 'containers_clean_on_deploy=["pihole"]'
```

The `-k` flag tells Ansible to prompt for the SSH password. Without it, Ansible only tries key-based authentication.

---

## Tag-Based Deployment

Use tags to run specific parts of the playbook. Tags automatically include their dependencies.

### Common Usage Patterns

```bash
cd dietpi/ansible

# Initial setup (base system + security)
ansible-playbook -i inventory.yml playbook.yml --tags base,security

# Install Docker only (no containers)
ansible-playbook -i inventory.yml playbook.yml --tags docker

# Deploy / update a specific container (auto-includes docker install if needed)
ansible-playbook -i inventory.yml playbook.yml --tags pihole
ansible-playbook -i inventory.yml playbook.yml --tags postgres
ansible-playbook -i inventory.yml playbook.yml --tags mariadb
ansible-playbook -i inventory.yml playbook.yml --tags mongodb
ansible-playbook -i inventory.yml playbook.yml --tags kafka
ansible-playbook -i inventory.yml playbook.yml --tags netdata
ansible-playbook -i inventory.yml playbook.yml --tags portainer
ansible-playbook -i inventory.yml playbook.yml --tags finances

# Clean deploy Pi-hole (wipes data, volumes, networks)
ansible-playbook -i inventory.yml playbook.yml --tags pihole -e 'containers_clean_on_deploy=["pihole"]'

# Update security configuration only
ansible-playbook -i inventory.yml playbook.yml --tags security

# Run specific role
ansible-playbook -i inventory.yml playbook.yml --tags network
ansible-playbook -i inventory.yml playbook.yml --tags openssh

# Pi-hole specific operations
ansible-playbook -i inventory.yml playbook.yml --tags pihole_cleanup
ansible-playbook -i inventory.yml playbook.yml --tags pihole_blocklists
```

### Available Tags

#### Base System
- `base` - Run all base system setup (network, system, users)
- `network` - Network configuration only
- `system` - System packages and updates only
- `users` - User management only

#### Containers
Each container has its own self-contained role. On first run it deploys fresh;
on subsequent runs it invokes the container's `update_<name>.sh` script
(backup → pull → restart → prune old images).

- `docker` - Install Docker engine + docker-compose plugin only
- `pihole` - Deploy / update Pi-hole (includes DNS config, sqlite3, blocklists, db maintenance)
- `postgres` - Deploy / update PostgreSQL (handles major version upgrades safely)
- `mariadb` - Deploy / update MariaDB (with pre-upgrade backup)
- `mongodb` - Deploy / update MongoDB (blocks non-sequential major upgrades)
- `kafka` - Deploy / update Kafka
- `netdata` - Deploy / update Netdata
- `portainer` - Deploy / update Portainer
- `finances` - Deploy / update Finances app

**Note**: All container tags auto-include the `docker` role (idempotent — only installs Docker if it's not already present).

#### Security
- `security` - Run all security hardening (openssh + firewall)
- `openssh` - SSH configuration and hardening only
- `firewall` - Firewall rules only

#### Specialized
- `pihole_cleanup` - Clean up Pi-hole database (prune old queries)
- `pihole_blocklists` - Sync Pi-hole blocklists
- `cleanup_dietpi` - Remove default dietpi user
- `cleanup` - Remove unused packages
- `reboot` - Reboot system

---

## Playbook Roles Order

| Order | Role        | Purpose                          | Dependencies                      |
|-------|-------------|----------------------------------|-----------------------------------|
| 1     | network     | Network configuration            | None                              |
|       |             | • Install NetworkManager         |                                   |
|       |             | • Configure static IPv6          |                                   |
| 2     | system      | Base system setup                | network                           |
|       |             | • Update package cache & upgrade |                                   |
|       |             | • Install initial packages       |                                   |
|       |             | • Update DietPi                  |                                   |
|       |             | • Set hostname                   |                                   |
| 3     | users       | User management                  | system                            |
|       |             | • Create new user                |                                   |
|       |             | • Set up shell & home directory  |                                   |
|       |             | • Upload common scripts          |                                   |
| 4     | openssh     | SSH hardening                    | users                             |
|       |             | • Configure SSH port & security  |                                   |
|       |             | • Add SSH public keys            |                                   |
|       |             | • Strong encryption settings     |                                   |
| 5     | firewall    | Base firewall setup              | openssh                           |
|       |             | • Install UFW                    |                                   |
|       |             | • Default deny incoming          |                                   |
|       |             | • Allow SSH                      |                                   |
|       |             | • Enable firewall                |                                   |
| 6     | docker      | Docker runtime installation      | users                             |
|       |             | • Install Docker                 |                                   |
|       |             | • Add user to docker group       |                                   |
|       |             | • Install docker-compose plugin  |                                   |
| 7     | <container> | Per-container deploy/update      | docker, firewall                  |
|       |             | • Upload compose + scripts       |                                   |
|       |             | • Start fresh or run update_*.sh |                                   |
|       |             | • Add own UFW port rules         |                                   |
|       |             | • pihole: also does DNS config,  |                                   |
|       |             |   sqlite3, blocklists, db prune  |                                   |
|       |             | • (pihole, postgres, mariadb,    |                                   |
|       |             |   mongodb, kafka, netdata,       |                                   |
|       |             |   portainer, finances)           |                                   |

---

## Configuration

Edit `group_vars/all.yml` to configure:

### Container Selection

Containers are selected via `--tags` at playbook runtime. No variable to maintain.

```bash
# Deploy a specific container
ansible-playbook -i inventory.yml playbook.yml --tags postgres

# Deploy multiple containers in one run
ansible-playbook -i inventory.yml playbook.yml --tags pihole,postgres,mariadb

# Deploy everything (full playbook, no tags)
ansible-playbook -i inventory.yml playbook.yml
```

### Clean Deploy (Wipe Container Data)

Control which containers to clean on deployment:

```yaml
# Don't clean any containers (default)
containers_clean_on_deploy: []

# Clean only Pi-hole
containers_clean_on_deploy:
  - pihole

# Clean multiple containers
containers_clean_on_deploy:
  - pihole
  - portainer
```

**What gets cleaned:**
- Container stopped and removed (`docker compose down -v`)
- All volumes deleted
- All networks deleted
- Container directory removed from `/opt/containers/`

**Use cases:**
- Pi-hole database corruption or too large
- Fresh start for specific container
- Testing clean deployment

**Command line override:**
```bash
# Override from command line (clean only pihole)
ansible-playbook -i inventory.yml playbook.yml --tags pihole -e 'containers_clean_on_deploy=["pihole"]'
```

### Other Settings
- Network configuration (IPv6, DNS)
- User accounts and SSH keys
- SSH port and security settings
- Firewall rules
- Pi-hole database retention
- Auto-reboot behavior


## Update Raspberry Pi Bootloader

Once inside the Raspberry Pi, run the following script to update the bootloader configuration
to enable PCIe support and other settings:

```bash
#!/usr/bin/env bash
cat > /tmp/boot.conf << 'EOF'
[all]
PCIE_PROBE=1
BOOT_UART=1
POWER_OFF_ON_HALT=0
BOOT_ORDER=0xf416
EOF
sudo rpi-eeprom-config --apply /tmp/boot.conf
sudo rpi-eeprom-update -a
vcgencmd bootloader_config
rm -f /tmp/boot.conf
```

---

## Troubleshooting

### SSH Connection Issues
- Ensure SSH keys are properly configured in `group_vars/all.yml`
- Use `-k` flag to prompt for password: `ansible-playbook -i inventory.yml playbook.yml -k`
- Check inventory.yml has correct IP address

### Pi-hole Slow Startup
- Run database cleanup: `--tags pihole_cleanup`
- Check database size: `docker exec pihole sqlite3 /etc/pihole/pihole-FTL.db "SELECT COUNT(*) FROM queries;"`
- Verify `maxDBdays: 30` in `pihole.toml`

### Container Deployment Issues
- Verify Docker is running: `docker ps`
- Check container logs: `docker logs <container_name>`
- Check update script logs: `/var/log/pihole-update.log` (pihole only)

### Firewall Lockout
- Ensure SSH port is allowed before enabling firewall
- Use serial console if locked out
- Firewall role runs LAST to prevent lockouts
