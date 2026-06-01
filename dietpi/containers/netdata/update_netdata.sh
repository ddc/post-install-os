#!/usr/bin/env bash
#
# Netdata Container Update Script
# Pulls latest image, recreates container, and prunes old images.
# Netdata is stateless (config only) — safe simple swap.
# Usage: bash update_netdata.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Netdata Update Script${NC}"
echo ""

if ! docker ps --format '{{.Names}}' | grep -q '^netdata$'; then
    echo -e "${YELLOW}Error: netdata container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

cd "${SCRIPT_DIR}"

echo -e "${GREEN}Pulling latest image...${NC}"
docker compose pull

echo -e "${GREEN}Recreating container...${NC}"
docker compose down
docker compose up -d

echo -e "${YELLOW}Waiting for netdata to be ready...${NC}"
for i in $(seq 1 30); do
    status=$(docker inspect --format='{{.State.Health.Status}}' netdata 2>/dev/null || echo "none")
    if [ "${status}" = "healthy" ] || [ "${status}" = "none" ]; then
        # "none" means no healthcheck defined; fall back to running check
        if docker ps --format '{{.Names}}' | grep -q '^netdata$'; then
            echo -e "${GREEN}netdata is ready!${NC}"
            break
        fi
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}Error: netdata did not become ready in time${NC}"
        exit 1
    fi
    sleep 5
done

echo -e "${GREEN}Removing old netdata images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! Netdata updated successfully.${NC}"
