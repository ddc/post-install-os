#!/usr/bin/env bash
#
# Home Assistant Container Update Script
# Backs up the config volume, pulls latest image, recreates container, prunes.
#
# Backup runs BEFORE any destructive action: HA migrates its config and
# SQLite recorder database on upgrade, and those migrations are not reversible.
# Downgrading the image after a migration leaves HA unable to read its own
# database, so the tarball is the only way back.
#
# Usage: bash update_homeassistant.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/homeassistant_backups"
BACKUP_FILE="${BACKUP_DIR}/homeassistant_$(date +%Y%m%d_%H%M%S).tar.gz"
KEEP_BACKUPS=5

echo -e "${GREEN}Home Assistant Update Script${NC}"
echo ""

if ! docker ps --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo -e "${YELLOW}Error: homeassistant container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

cd "${SCRIPT_DIR}"

HA_PORT=$(grep '^HA_PORT=' .env | cut -d '=' -f 2)
HA_PORT="${HA_PORT:-8123}"

##### BACKUP #####

mkdir -p "${BACKUP_DIR}"
echo -e "${GREEN}Creating backup at ${BACKUP_FILE}...${NC}"

# Stop first so the recorder database is not copied mid-write.
docker compose stop

docker run --rm \
    -v homeassistant_config:/config:ro \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3 \
    tar czf "/backup/$(basename "${BACKUP_FILE}")" -C /config .

echo -e "${GREEN}Backup size: $(du -h "${BACKUP_FILE}" | cut -f1)${NC}"

# Keep the most recent KEEP_BACKUPS tarballs, drop the rest.
if [ "$(ls -1t "${BACKUP_DIR}"/homeassistant_*.tar.gz 2>/dev/null | wc -l)" -gt "${KEEP_BACKUPS}" ]; then
    echo -e "${GREEN}Pruning old backups (keeping ${KEEP_BACKUPS})...${NC}"
    ls -1t "${BACKUP_DIR}"/homeassistant_*.tar.gz | tail -n "+$((KEEP_BACKUPS + 1))" | xargs -r rm -f
fi

##### UPGRADE #####

echo -e "${GREEN}Pulling latest image...${NC}"
docker compose pull

echo -e "${GREEN}Recreating container...${NC}"
docker compose down
docker compose up -d

echo -e "${YELLOW}Waiting for Home Assistant to be ready (can take a few minutes)...${NC}"
for i in $(seq 1 60); do
    status=$(docker inspect --format='{{.State.Health.Status}}' homeassistant 2>/dev/null || echo "none")
    if [ "${status}" = "healthy" ]; then
        echo -e "${GREEN}Home Assistant is ready!${NC}"
        break
    fi
    if [ "${status}" = "none" ]; then
        # No healthcheck defined; fall back to a running check.
        if docker ps --format '{{.Names}}' | grep -q '^homeassistant$'; then
            echo -e "${GREEN}Home Assistant is running (no healthcheck defined)${NC}"
            break
        fi
    fi
    if [ "$i" -eq 60 ]; then
        echo -e "${RED}Error: Home Assistant did not become healthy in time${NC}"
        echo -e "${YELLOW}Backup is at: ${BACKUP_FILE}${NC}"
        echo -e "${YELLOW}Logs: docker logs homeassistant --tail 50${NC}"
        echo -e "${YELLOW}To roll back, see the Restore section in README.md${NC}"
        exit 1
    fi
    sleep 5
done

echo -e "${GREEN}Removing old homeassistant images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! Home Assistant updated successfully.${NC}"
echo -e "${GREEN}UI: http://$(hostname -I | awk '{print $1}'):${HA_PORT}${NC}"
echo -e "${GREEN}Backup kept at: ${BACKUP_FILE}${NC}"
