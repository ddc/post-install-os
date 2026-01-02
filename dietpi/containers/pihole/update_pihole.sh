#!/usr/bin/env bash
#
# Pi-hole Container Update Script
# Updates Docker image and gravity database
# Usage: bash update_pihole.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Pi-hole Update Script${NC}"
echo ""

# Check if container is running
if ! docker ps | grep -q pihole; then
    echo -e "${YELLOW}Error: Pi-hole container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

# Pull latest Pi-hole image
echo -e "${GREEN}Pulling latest Pi-hole image...${NC}"
cd "$SCRIPT_DIR"
docker compose pull

# Recreate container with new image
echo -e "${GREEN}Recreating Pi-hole container...${NC}"
docker compose down
docker compose up -d

# Wait for container to be healthy
echo -e "${YELLOW}Waiting for Pi-hole to be ready...${NC}"
sleep 10

# Update gravity database
echo -e "${GREEN}Updating gravity database (this may take a few minutes)...${NC}"
docker exec pihole pihole -g

echo ""
echo -e "${GREEN}Done! Pi-hole updated successfully.${NC}"
echo "Container version:"
docker exec pihole pihole -v | head -3
