#!/usr/bin/env bash
#
# MariaDB Container Update Script
# Backs up all databases, pulls latest image, recreates container, and prunes old images.
# On major version upgrade, backup is taken BEFORE any destructive action.
# Usage: bash update_mariadb.sh [--yes|-y]
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/mariadb_backups"
BACKUP_FILE="${BACKUP_DIR}/mariadb_$(date +%Y%m%d_%H%M%S).sql"

ASSUME_YES=0
if [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
    ASSUME_YES=1
fi

echo -e "${GREEN}MariaDB Update Script${NC}"
echo ""

if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${SCRIPT_DIR}/.env"
    set +a
else
    echo -e "${RED}Error: .env file not found in ${SCRIPT_DIR}${NC}"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^mariadb$'; then
    echo -e "${YELLOW}Error: mariadb container is not running${NC}"
    exit 1
fi

CURRENT_VERSION=$(docker exec mariadb mariadbd --version 2>/dev/null | grep -oP 'Ver \K[0-9]+\.[0-9]+' | head -1)
echo -e "${GREEN}Current MariaDB version: ${CURRENT_VERSION}${NC}"

TARGET_IMAGE=$(grep -E '^\s*image:\s*mariadb:' "${SCRIPT_DIR}/docker-compose.yml" | awk -F'mariadb:' '{print $2}' | tr -d ' ')
echo -e "${GREEN}Target image: mariadb:${TARGET_IMAGE}${NC}"
echo ""

mkdir -p "${BACKUP_DIR}"
echo -e "${GREEN}Creating backup at ${BACKUP_FILE}...${NC}"
docker exec mariadb mariadb-dump \
    -u root -p"${MARIADB_PASSWORD}" \
    --all-databases --single-transaction --routines --triggers --events \
    > "${BACKUP_FILE}" 2>/dev/null
echo -e "${GREEN}Backup size: $(du -h "${BACKUP_FILE}" | cut -f1)${NC}"
echo ""

# MariaDB handles minor upgrades in place (runs mysql_upgrade on start).
# Major upgrades (e.g., 10 -> 11) are usually supported in place too, but
# skipping versions is not. Warn and require confirmation.
TARGET_MAJOR=$(echo "${TARGET_IMAGE}" | cut -d. -f1)
if [ -n "${CURRENT_VERSION}" ] && [ -n "${TARGET_MAJOR}" ]; then
    CURRENT_MAJOR=$(echo "${CURRENT_VERSION}" | cut -d. -f1)
    if [ "${CURRENT_MAJOR}" != "${TARGET_MAJOR}" ]; then
        echo -e "${YELLOW}WARNING: Major version change (${CURRENT_MAJOR} -> ${TARGET_MAJOR})${NC}"
        echo -e "${YELLOW}MariaDB supports in-place major upgrades only between adjacent versions.${NC}"
        echo -e "${YELLOW}Backup is at: ${BACKUP_FILE}${NC}"
        if [ "${ASSUME_YES}" -ne 1 ]; then
            read -rp "Proceed? [y/N] " confirm
            if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
                echo -e "${YELLOW}Aborted.${NC}"
                exit 0
            fi
        fi
    fi
fi

cd "${SCRIPT_DIR}"

echo -e "${GREEN}Pulling new image...${NC}"
docker compose pull

echo -e "${GREEN}Stopping container...${NC}"
docker compose down

echo -e "${GREEN}Starting new container...${NC}"
docker compose up -d

echo -e "${YELLOW}Waiting for mariadb to be ready...${NC}"
for i in $(seq 1 30); do
    if docker inspect --format='{{.State.Health.Status}}' mariadb 2>/dev/null | grep -q healthy; then
        echo -e "${GREEN}mariadb is ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}Error: mariadb did not become healthy. Backup at ${BACKUP_FILE}${NC}"
        exit 1
    fi
    sleep 5
done

echo -e "${GREEN}Removing dangling mariadb images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! MariaDB updated successfully.${NC}"
echo "New version:"
docker exec mariadb mariadbd --version
echo -e "${GREEN}Backup kept at: ${BACKUP_FILE}${NC}"
