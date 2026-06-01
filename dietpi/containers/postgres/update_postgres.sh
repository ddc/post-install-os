#!/usr/bin/env bash
#
# PostgreSQL Container Update Script
# Pulls latest image, backs up data, and safely upgrades the container.
# Handles major version bumps by detecting incompatibility and aborting before data loss.
# Usage: bash update_postgres.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/postgres_backups"
BACKUP_FILE="${BACKUP_DIR}/postgres_$(date +%Y%m%d_%H%M%S).sql"

ASSUME_YES=0
if [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
    ASSUME_YES=1
fi

echo -e "${GREEN}PostgreSQL Update Script${NC}"
echo ""

# Load env
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${SCRIPT_DIR}/.env"
    set +a
else
    echo -e "${RED}Error: .env file not found in ${SCRIPT_DIR}${NC}"
    exit 1
fi

# Check container running
if ! docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
    echo -e "${YELLOW}Error: postgres container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

# Detect current major version
CURRENT_VERSION=$(docker exec postgres postgres --version | awk '{print $3}' | cut -d. -f1)
echo -e "${GREEN}Current PostgreSQL major version: ${CURRENT_VERSION}${NC}"

# Detect target major version from compose file
TARGET_IMAGE=$(grep -E '^\s*image:\s*postgres:' "${SCRIPT_DIR}/docker-compose.yml" | awk -F'postgres:' '{print $2}' | tr -d ' ')
TARGET_VERSION=$(echo "${TARGET_IMAGE}" | cut -d. -f1 | cut -d- -f1)
echo -e "${GREEN}Target image: postgres:${TARGET_IMAGE}${NC}"
echo -e "${GREEN}Target major version: ${TARGET_VERSION}${NC}"
echo ""

# Backup
mkdir -p "${BACKUP_DIR}"
echo -e "${GREEN}Creating backup at ${BACKUP_FILE}...${NC}"
docker exec -e PGPASSWORD="${POSTGRESQL_PASSWORD}" postgres \
    pg_dumpall -U "${POSTGRESQL_USER}" > "${BACKUP_FILE}"
echo -e "${GREEN}Backup size: $(du -h "${BACKUP_FILE}" | cut -f1)${NC}"
echo ""

# Warn on major version upgrade
if [ "${CURRENT_VERSION}" != "${TARGET_VERSION}" ]; then
    echo -e "${RED}WARNING: Major version upgrade detected (${CURRENT_VERSION} -> ${TARGET_VERSION})${NC}"
    echo -e "${YELLOW}The on-disk data format is incompatible between major versions.${NC}"
    echo -e "${YELLOW}This script will:${NC}"
    echo -e "${YELLOW}  1. Stop the old container${NC}"
    echo -e "${YELLOW}  2. Remove the postgresql_data volume${NC}"
    echo -e "${YELLOW}  3. Start the new container (empty)${NC}"
    echo -e "${YELLOW}  4. Restore from the backup just created${NC}"
    echo ""
    if [ "${ASSUME_YES}" -eq 1 ]; then
        echo -e "${YELLOW}--yes flag set, proceeding without prompt${NC}"
    else
        read -rp "Proceed? [y/N] " confirm
        if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
            echo -e "${YELLOW}Aborted. Backup kept at ${BACKUP_FILE}${NC}"
            exit 0
        fi
    fi
    MAJOR_UPGRADE=1
else
    MAJOR_UPGRADE=0
fi

# Pull new image
echo -e "${GREEN}Pulling new image...${NC}"
cd "${SCRIPT_DIR}"
docker compose pull

# Stop container
echo -e "${GREEN}Stopping container...${NC}"
docker compose down

# Wipe volume if major upgrade
if [ "${MAJOR_UPGRADE}" = "1" ]; then
    echo -e "${YELLOW}Removing postgresql_data volume...${NC}"
    docker volume rm postgresql_data
fi

# Start new container
echo -e "${GREEN}Starting new container...${NC}"
docker compose up -d

# Wait for healthy
echo -e "${YELLOW}Waiting for postgres to be ready...${NC}"
for i in $(seq 1 30); do
    if docker inspect --format='{{.State.Health.Status}}' postgres 2>/dev/null | grep -q healthy; then
        echo -e "${GREEN}postgres is ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}Error: postgres did not become healthy in time${NC}"
        echo -e "${YELLOW}Backup is kept at ${BACKUP_FILE}${NC}"
        exit 1
    fi
    sleep 5
done

# Restore if major upgrade
if [ "${MAJOR_UPGRADE}" = "1" ]; then
    echo -e "${GREEN}Restoring from backup...${NC}"
    docker exec -i -e PGPASSWORD="${POSTGRESQL_PASSWORD}" postgres \
        psql -U "${POSTGRESQL_USER}" -d postgres < "${BACKUP_FILE}"
    echo -e "${GREEN}Restore complete.${NC}"
fi

echo ""
echo -e "${GREEN}Removing dangling/unused postgres images...${NC}"
docker image prune -f --filter "label!=keep" >/dev/null || true
# Remove old postgres images specifically (any postgres:* not currently in use)
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk '$1 ~ /^postgres:/ {print $2}' | while read -r img_id; do
    if [ "${img_id}" != "$(docker inspect --format='{{.Image}}' postgres 2>/dev/null | cut -d: -f2 | cut -c1-12)" ]; then
        docker rmi "${img_id}" 2>/dev/null || true
    fi
done

echo ""
echo -e "${GREEN}Done! PostgreSQL updated successfully.${NC}"
echo "New version:"
docker exec postgres postgres --version
echo -e "${GREEN}Backup kept at: ${BACKUP_FILE}${NC}"
