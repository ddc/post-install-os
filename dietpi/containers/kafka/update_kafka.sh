#!/usr/bin/env bash
#
# Kafka Container Update Script
# Pulls latest image, recreates container, and prunes old images.
# WARNING: Kafka major version upgrades can change log format. Check release
# notes before bumping the image tag. This script does NOT handle log format
# migrations automatically.
# Usage: bash update_kafka.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Kafka Update Script${NC}"
echo ""

if ! docker ps --format '{{.Names}}' | grep -q '^kafka$'; then
    echo -e "${YELLOW}Error: kafka container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

CURRENT_VERSION=$(docker exec kafka bash -c 'ls /usr/share/java/kafka/kafka_*.jar 2>/dev/null | head -1 | grep -oP "kafka_\K[0-9.-]+" | head -1' || echo "unknown")
echo -e "${GREEN}Current Kafka version: ${CURRENT_VERSION}${NC}"

cd "${SCRIPT_DIR}"

echo -e "${GREEN}Pulling latest image...${NC}"
docker compose pull

echo -e "${GREEN}Recreating container...${NC}"
docker compose down
docker compose up -d

echo -e "${YELLOW}Waiting for kafka to be ready...${NC}"
for i in $(seq 1 40); do
    if docker inspect --format='{{.State.Health.Status}}' kafka 2>/dev/null | grep -q healthy; then
        echo -e "${GREEN}kafka is ready!${NC}"
        break
    fi
    if [ "$i" -eq 40 ]; then
        echo -e "${RED}Error: kafka did not become healthy in time${NC}"
        echo -e "${YELLOW}Check logs: docker logs kafka${NC}"
        exit 1
    fi
    sleep 5
done

echo -e "${GREEN}Removing dangling images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! Kafka updated successfully.${NC}"
