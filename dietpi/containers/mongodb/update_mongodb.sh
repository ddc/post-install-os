#!/usr/bin/env bash
#
# MongoDB Container Update Script
# Backs up all databases via mongodump, pulls latest image, recreates container.
# WARNING: MongoDB major version upgrades MUST be done sequentially (e.g., 6->7->8,
# never 6->8). This script will warn and abort if you try to skip a major version.
# Usage: bash update_mongodb.sh [--yes|-y]
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/mongodb_backups"
BACKUP_PATH="${BACKUP_DIR}/mongodb_$(date +%Y%m%d_%H%M%S)"

ASSUME_YES=0
if [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
    ASSUME_YES=1
fi

echo -e "${GREEN}MongoDB Update Script${NC}"
echo ""

if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${SCRIPT_DIR}/.env"
    set +a
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^mongodb$'; then
    echo -e "${YELLOW}Error: mongodb container is not running${NC}"
    exit 1
fi

CURRENT_VERSION=$(docker exec mongodb mongod --version 2>/dev/null | grep 'db version' | grep -oP 'v\K[0-9]+\.[0-9]+' | head -1)
CURRENT_MAJOR=$(echo "${CURRENT_VERSION}" | cut -d. -f1)
echo -e "${GREEN}Current MongoDB version: ${CURRENT_VERSION}${NC}"

TARGET_IMAGE=$(grep -E '^\s*image:\s*mongo:' "${SCRIPT_DIR}/docker-compose.yml" | awk -F'mongo:' '{print $2}' | tr -d ' ')
TARGET_MAJOR=$(echo "${TARGET_IMAGE}" | cut -d. -f1)
echo -e "${GREEN}Target image: mongo:${TARGET_IMAGE}${NC}"
echo ""

# Block non-sequential major upgrades
if [ -n "${CURRENT_MAJOR}" ] && [ -n "${TARGET_MAJOR}" ]; then
    DIFF=$((TARGET_MAJOR - CURRENT_MAJOR))
    if [ "${DIFF}" -gt 1 ]; then
        echo -e "${RED}ERROR: Cannot skip major versions (${CURRENT_MAJOR} -> ${TARGET_MAJOR})${NC}"
        echo -e "${RED}MongoDB requires sequential upgrades. Upgrade to major version $((CURRENT_MAJOR + 1)) first.${NC}"
        exit 1
    fi
fi

mkdir -p "${BACKUP_DIR}"
echo -e "${GREEN}Creating backup at ${BACKUP_PATH}...${NC}"
docker exec mongodb mongodump \
    --username "${MONGODB_USER}" --password "${MONGODB_PASSWORD}" \
    --authenticationDatabase admin \
    --archive > "${BACKUP_PATH}.archive" 2>/dev/null
echo -e "${GREEN}Backup size: $(du -h "${BACKUP_PATH}.archive" | cut -f1)${NC}"
echo ""

if [ -n "${CURRENT_MAJOR}" ] && [ -n "${TARGET_MAJOR}" ] && [ "${CURRENT_MAJOR}" != "${TARGET_MAJOR}" ]; then
    echo -e "${YELLOW}WARNING: Major version upgrade (${CURRENT_MAJOR} -> ${TARGET_MAJOR})${NC}"
    echo -e "${YELLOW}After upgrade, you may need to set featureCompatibilityVersion manually:${NC}"
    echo -e "${YELLOW}  docker exec mongodb mongosh --eval 'db.adminCommand({setFeatureCompatibilityVersion: \"${TARGET_MAJOR}.0\"})'${NC}"
    if [ "${ASSUME_YES}" -ne 1 ]; then
        read -rp "Proceed? [y/N] " confirm
        if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
            echo -e "${YELLOW}Aborted.${NC}"
            exit 0
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

echo -e "${YELLOW}Waiting for mongodb to be ready...${NC}"
for i in $(seq 1 30); do
    if docker inspect --format='{{.State.Health.Status}}' mongodb 2>/dev/null | grep -q healthy; then
        echo -e "${GREEN}mongodb is ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}Error: mongodb did not become healthy. Backup at ${BACKUP_PATH}.archive${NC}"
        exit 1
    fi
    sleep 5
done

echo -e "${GREEN}Removing dangling mongo images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! MongoDB updated successfully.${NC}"
echo "New version:"
docker exec mongodb mongod --version | head -1
echo -e "${GREEN}Backup kept at: ${BACKUP_PATH}.archive${NC}"
