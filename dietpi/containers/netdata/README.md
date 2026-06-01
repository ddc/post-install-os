# Netdata Container

Real-time performance monitoring and troubleshooting for systems and applications.

## Features

- ✅ Real-time system monitoring (CPU, RAM, disk, network)
- ✅ Docker container monitoring
- ✅ Low overhead (~1% CPU, minimal RAM)
- ✅ Beautiful web dashboard
- ✅ Thousands of metrics with zero configuration
- ✅ Anomaly detection
- ✅ Optional Netdata Cloud integration

## Configuration

### Environment Variables (.env)

```env
NETDATA_PORT=19999                  # Web interface port
NETDATA_CLAIM_TOKEN=                # Optional: Netdata Cloud claim token
NETDATA_CLAIM_ROOMS=                # Optional: Netdata Cloud room ID
NETDATA_CLAIM_URL=https://app.netdata.cloud
```

### Ports

- **19999**: Web interface (HTTP)

## Access

After deployment, access Netdata at:
- **Local**: `http://localhost:19999`
- **Remote**: `http://<raspberry-pi-ip>:19999`

## Netdata Cloud (Optional)

To connect your Netdata instance to Netdata Cloud for remote monitoring:

1. Create a free account at [https://app.netdata.cloud](https://app.netdata.cloud)
2. Create a Space and Room
3. Get your claim token from the "Add Nodes" section
4. Update `.env` file:
   ```env
   NETDATA_CLAIM_TOKEN=your-token-here
   NETDATA_CLAIM_ROOMS=your-room-id
   ```
5. Restart the container:
   ```bash
   cd /opt/containers/netdata
   docker compose down
   docker compose up -d
   ```


## Volume Mounts

The container has access to:
- `/proc` - Process information
- `/sys` - System information
- `/var/log` - System logs (read-only)
- `/var/run/docker.sock` - Docker monitoring (read-only)
- `/etc/passwd`, `/etc/group` - User information (read-only)

## Performance Impact

Netdata is designed to be lightweight:
- **CPU**: ~1% on average
- **RAM**: ~50-100 MB
- **Disk**: Minimal (configurable retention)

## Security Considerations

### Capabilities
The container requires:
- `SYS_PTRACE`: To monitor processes
- `SYS_ADMIN`: To access system information

### AppArmor
AppArmor is disabled for this container to allow full system monitoring.

### Network
- Runs on isolated `netdata_network`
- Web interface is HTTP only (use reverse proxy for HTTPS)

## Customization

### Config Files
Configuration files are stored in the `netdata_config` volume. To customize:

```bash
# Access the container
docker exec -it netdata bash

# Edit config (main config)
cd /etc/netdata
vi netdata.conf

# Restart to apply changes
docker restart netdata
```

### Disable Collectors
To reduce overhead, you can disable collectors you don't need:

```bash
# Edit collector config
docker exec -it netdata bash -c "cd /etc/netdata && vi python.d.conf"
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs
docker logs netdata

# Check permissions
ls -la /var/run/docker.sock
```

### Can't Access Web Interface
```bash
# Verify container is running
docker ps | grep netdata

# Check port binding
docker port netdata

# Test locally
curl http://localhost:19999
```

### High Resource Usage
```bash
# Check configured retention (default is 1 hour)
docker exec netdata cat /etc/netdata/netdata.conf | grep history

# Reduce retention if needed
docker exec netdata sh -c "echo '[db]
  mode = dbengine
  retention = 3600' >> /etc/netdata/netdata.conf"

docker restart netdata
```

## Health Check

The container includes a healthcheck that verifies the API is responding:
```bash
# Check health status
docker inspect netdata | grep -A 10 Health
```

## Updates

```bash
cd /opt/containers/netdata
docker compose pull
docker compose up -d
```

## Uninstall

```bash
cd /opt/containers/netdata
docker compose down -v  # -v removes volumes
```
