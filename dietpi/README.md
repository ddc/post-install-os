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
# Initial setup (base system + security)
ansible-playbook -i inventory.yml playbook.yml --tags base,security

# Deploy Pi-hole specifically (includes docker + post_docker automatically)
ansible-playbook -i inventory.yml playbook.yml --tags pihole

# Deploy all containers defined in containers_installs
ansible-playbook -i inventory.yml playbook.yml --tags docker

# Clean deploy specific containers (wipes data, volumes, networks)
ansible-playbook -i inventory.yml playbook.yml --tags pihole -e 'containers_clean_on_deploy=["pihole"]'
ansible-playbook -i inventory.yml playbook.yml --tags docker -e 'containers_clean_on_deploy=["kafka","mariadb"]'

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
- `docker` - Deploy all containers (docker + post_docker + deploys all containers in `containers_installs`)
- `post_docker` - Post-deployment tasks only (DNS, sqlite3, blocklists, etc.)
- `pihole` - Deploy Pi-hole specifically (auto-includes docker + post_docker)

**Note**: Container deployment is controlled by `containers_installs` in `group_vars/all.yml`. Use:
- `--tags docker` to deploy all uncommented containers
- `--tags pihole` to deploy only Pi-hole (regardless of `containers_installs`)

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
| 4     | pihole      | Pi-hole pre-configuration        | users                             |
|       |             | • Prepare Pi-hole configs        |                                   |
| 5     | docker      | Container platform               | users                             |
|       |             | • Install Docker                 |                                   |
|       |             | • Add user to docker group       |                                   |
|       |             | • Deploy container configs       |                                   |
| 6     | post_docker | Container post-deployment        | docker                            |
|       |             | • Wait for containers to start   |                                   |
|       |             | • Configure DNS (Pi-hole)        |                                   |
|       |             | • Install sqlite3 in Pi-hole     |                                   |
|       |             | • Sync blocklists                |                                   |
|       |             | • Database cleanup               |                                   |
| 7     | openssh     | SSH hardening                    | users                             |
|       |             | • Configure SSH port & security  |                                   |
|       |             | • Add SSH public keys            |                                   |
|       |             | • Strong encryption settings     |                                   |
| 8     | firewall    | Security rules                   | ALL services configured           |
|       |             | • Install UFW                    |                                   |
|       |             | • Read container .env files      |                                   |
|       |             | • Configure firewall rules       |                                   |
|       |             | • Enable firewall safely         |                                   |

---

## Configuration

Edit `group_vars/all.yml` to configure:

### Container Selection
```yaml
containers_installs:
#  - kafka
#  - mongodb
#  - mysql
#  - netdata
  - pihole
#  - portainer
#  - postgres
```
Uncomment the containers you want to deploy.

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
- Check `containers_installs` in `group_vars/all.yml`
- Verify Docker is running: `docker ps`
- Check logs: `docker logs <container_name>`

### Firewall Lockout
- Ensure SSH port is allowed before enabling firewall
- Use serial console if locked out
- Firewall role runs LAST to prevent lockouts
