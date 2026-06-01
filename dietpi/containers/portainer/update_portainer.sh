#!/usr/bin/env bash
#
# Portainer Container Update Script
# Pulls latest image, recreates container, and prunes old images.
# Portainer stores config in a named volume — updates are safe, config persists.
# Usage: bash update_portainer.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Portainer Update Script${NC}"
echo ""

if ! docker ps --format '{{.Names}}' | grep -q '^portainer$'; then
    echo -e "${YELLOW}Error: portainer container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

cd "${SCRIPT_DIR}"

echo -e "${GREEN}Pulling latest image...${NC}"
docker compose pull

echo -e "${GREEN}Recreating container...${NC}"
docker compose down
docker compose up -d

echo -e "${YELLOW}Waiting for portainer to be ready...${NC}"
for i in $(seq 1 30); do
    if docker ps --format '{{.Names}}' | grep -q '^portainer$'; then
        echo -e "${GREEN}portainer is ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}Error: portainer did not become ready in time${NC}"
        exit 1
    fi
    sleep 5
done

echo -e "${GREEN}Removing old portainer images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! Portainer updated successfully.${NC}"
