# Home Assistant Docker Container

Home automation platform. This is **HA Container**, not HA OS or Supervised, so
there is no add-on store — add-ons are separate containers here instead (e.g.
Zigbee2MQTT, Mosquitto), and HA's own Backup integration works but cannot
snapshot the host.

## Configuration

### Environment Variables (.env)

- `TZ`: Timezone
- `HA_PORT`: Web UI port (default: 8123)
- `ZIGBEE_DEVICE`: Zigbee coordinator by-id path (empty until the dongle exists)

### Host networking

The container runs with `network_mode: host`. That is required for:

- device auto-discovery (mDNS/Bonjour, SSDP/UPnP) — Chromecast, Sonos, Hue,
  ESPHome, printers
- the HomeKit bridge and Matter
- any integration that broadcasts on the LAN

The cost is no network isolation: HA binds `${HA_PORT}` on the host directly,
and `roles/homeassistant` opens that port in UFW.

### Bluetooth

Not enabled. Bluetooth is optional in HA and nothing here needs it — Zigbee
does not use it, and BLE range on a Pi is roughly one room. On DietPi the
`bluetooth` service ships inactive, so leaving it off costs nothing.

To enable BLE integrations (SwitchBot, BLE-only Xiaomi/Govee sensors, room
presence) later:

```bash
# 1. host side
sudo systemctl enable --now bluetooth
bluetoothctl list                      # confirm an adapter exists
ls -l /run/dbus/system_bus_socket      # confirm the socket exists
```

2. uncomment the `/run/dbus:/run/dbus:ro` volume in `docker-compose.yml`
3. `docker compose up -d`

Read-only is correct for that mount — connecting to a unix socket is not a
filesystem write. If `/run/dbus` is absent, Docker silently creates an empty
directory and the integration fails confusingly, so check before uncommenting.

## Usage

```bash
docker compose up -d              # start
docker compose logs -f            # follow logs (watch the first boot here)
bash update_homeassistant.sh      # backup + pull + recreate + prune
```

First boot takes several minutes on a Pi 5 while HA installs integration
dependencies. The UI is at `http://<pi-ip>:8123` and walks through onboarding.

## Adding the Zigbee dongle (Sonoff ZBDongle-E / EFR32MG24)

The compose file ships with the `devices:` block commented out, so the stack
runs fine with no dongle attached. When it arrives:

```bash
# 1. plug it in, then find its stable path
ls -l /dev/serial/by-id/
# e.g. usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_abc123-if00-port0
```

```bash
# 2. put that full path in .env
ZIGBEE_DEVICE=/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_abc123-if00-port0
```

3. uncomment the `devices:` block in `docker-compose.yml`
4. `docker compose up -d`

Use the `/dev/serial/by-id/` path, never `/dev/ttyUSB0` or `/dev/ttyACM0`:
those are assigned in probe order and change after a reboot or a re-plug, which
silently points HA at the wrong device.

Mirror both changes into this repo (`containers/homeassistant/`) so a redeploy
keeps them — Ansible copies these files over the ones on the Pi.

**Firmware note:** the MG24 ("ZBDongle-E") ships with EmberZNet firmware and
appears in HA as a ZHA "EZSP" coordinator. Zigbee2MQTT also supports it, but
needs its own container plus an MQTT broker. ZHA inside HA is the simpler start.

## Backups

`update_homeassistant.sh` tars the whole `/config` volume to
`~/homeassistant_backups/` before upgrading, keeping the last 5. It stops the
container first so the recorder database is not copied mid-write.

This matters because HA migrates its config and SQLite database on upgrade, and
those migrations are **not reversible** — pulling an older image after a
migration leaves HA unable to read its own database.

### Restore

```bash
docker compose down
docker run --rm \
    -v homeassistant_config:/config \
    -v "${HOME}/homeassistant_backups:/backup" \
    alpine:3 \
    sh -c "rm -rf /config/* /config/..?* && tar xzf /backup/homeassistant_<timestamp>.tar.gz -C /config"
```

Then pin the previous tag in `docker-compose.yml` (`image:` line) and
`docker compose up -d`. Restoring config without also rolling the image back
leaves the newer HA looking at an older database.

## Troubleshooting

**UI unreachable.** Check the container is healthy and the port is open:

```bash
docker ps --filter name=homeassistant
curl -sI http://127.0.0.1:8123
sudo ufw status | grep 8123
```

**Devices not discovered.** Confirm host networking is in effect — with
`network_mode: host`, `docker ps` shows no port mappings for this container. If
you see `0.0.0.0:8123->8123/tcp`, it is on a bridge network and discovery will
not work.

**Dongle not found after a reboot.** The `ZIGBEE_DEVICE` path changed. Re-check
`ls -l /dev/serial/by-id/` and confirm `.env` uses a by-id path.
