# Pi-hole Docker Container

Pi-hole network-wide ad blocking via DNS sinkhole.

## Configuration

### Environment Variables (.env)

- `TZ`: Timezone (e.g., `America/Sao_Paulo`, `America/New_York`)
- `WEBPASSWORD`: Admin password for web interface
- `WEB_PORT`: Web interface port (default: 80)

**Note**: Pi-hole v6 uses `pihole.toml` for most configuration. See the TOML file for DNS, DNSSEC, caching, and other settings.

### Configuration File (pihole.toml)

Pi-hole v6 uses a centralized TOML configuration file for:
- DNS servers and settings (DNSSEC, query logging)
- Cache configuration
- Rate limiting
- Blocking behavior
- Database settings
- Webserver settings

See `pihole.toml` for all available options and comments.

### Network Mode

This container uses **host network mode** to:
- Bind directly to port 53 (DNS)
- Avoid port conflicts with system DNS
- Ensure proper DNS resolution for all devices

## Deployment

```bash
# Start Pi-hole
docker compose up -d

# Import blocklists (first time or when adding new lists)
bash import_blocklists.sh

# View logs
docker compose logs -f

# Stop Pi-hole
docker compose down

# Update Pi-hole container and gravity
bash update_pihole.sh
```

### Managing Blocklists

Pi-hole v6 stores blocklists in the gravity.db database. You can manage them in two ways:

**1. Pre-configured Lists (Recommended for initial setup)**

### Blocklist Management
Blocklists are managed via `common/containers/pihole/blocklists.txt`:
- Edit the file to add/remove blocklists
- Sync with Ansible: `--tags pihole_blocklists`
- Or run manually: `bash import_blocklists.sh` (in Pi-hole directory)

Edit `blocklists.txt` to add or remove blocklist URLs, then run:
```bash
bash import_blocklists.sh
```

This script will:
- Import URLs from `blocklists.txt` into gravity.db
- Skip URLs that already exist
- Update the gravity database
- Show a summary of added/skipped lists

**2. Web Interface**

Add blocklists manually via the web interface:
- Go to **Adlists** → **Add a new adlist**
- Enter the blocklist URL
- Click **Add**
- Update gravity (Settings → Update Gravity)

## Access

- **Web Interface**: `http://<raspberry-pi-ip>/admin`
- **Password**: Set in `.env` file

## Router Configuration

Configure your router to use the Pi-hole as DNS server:

- **Primary DNS (IPv4)**: `<raspberry-pi-ip>` (e.g., 192.168.1.100)
- **Secondary DNS (IPv6)**: `<raspberry-pi-ipv6>` (if configured)


## Advanced Configuration

### Custom DNS Records

Edit `./dnsmasq.d/02-custom.conf`:
```
# Custom DNS record
address=/homeserver.local/192.168.1.50
```

### Database Cleanup
The playbook includes intelligent database cleanup:
- Automatically runs when database > 100K queries
- Deletes queries older than 30 days
- Reclaims disk space with VACUUM

Run manually:
```bash
ansible-playbook -i inventory.yml playbook.yml --tags pihole_cleanup
```

### Manual Database Purge
To reset Pi-hole query statistics or remove historical data:

**Purge All Queries (Fresh Start)**
```bash
# Remove the database file (it will be recreated fresh)                                                                                                                                                                       
docker exec pihole rm /etc/pihole/pihole-FTL.db                                                                                                                                                                               
                                                                                                                                                                                                                            
# Restart Pi-hole (will create fresh database)                                                                                                                                                                                  
docker restart pihole   
```
This will:
- Delete all historical queries
- Reset "Top Clients" statistics to zero
- Start fresh tracking from now
- Keep all blocklists and settings

### sqlite3 Installation
sqlite3 is permanently installed in the Pi-hole container for:
- Blocklist management
- Database cleanup operations
- Custom queries

### Block Additional Domains

Use the web interface or add to blocklists via `blocklists.txt` (see Managing Blocklists section).

### Recommended Blocklist Sources

- [StevenBlack's Hosts](https://github.com/StevenBlack/hosts) - Unified hosts file
- [Hagezi DNS Blocklists](https://github.com/hagezi/dns-blocklists) - Comprehensive lists
- [OISD](https://oisd.nl/) - Optimized blocklists
- [The Block List Project](https://github.com/blocklistproject/Lists) - Categorized lists
- [Firebog](https://firebog.net/) - Curated blocklist collection
