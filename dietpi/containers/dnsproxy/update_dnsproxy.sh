#!/usr/bin/env bash
#
# DNS-over-HTTPS Proxy Update Script
# Pulls latest image, recreates container, verifies it resolves, prunes images.
# Stateless (no volumes) — safe simple swap.
#
# Usage: bash update_dnsproxy.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}DNS Proxy Update Script${NC}"
echo ""

if ! docker ps --format '{{.Names}}' | grep -q '^dnsproxy$'; then
    echo -e "${YELLOW}Error: dnsproxy container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

cd "${SCRIPT_DIR}"

DNSPROXY_PORT=$(grep '^DNSPROXY_PORT=' .env | cut -d '=' -f 2)
DNSPROXY_PORT="${DNSPROXY_PORT:-5053}"

echo -e "${GREEN}Pulling latest image...${NC}"
docker compose pull

echo -e "${GREEN}Recreating container...${NC}"
docker compose down
docker compose up -d

echo -e "${YELLOW}Waiting for dnsproxy to resolve...${NC}"
for i in $(seq 1 20); do
    if dig +short +time=3 +tries=1 "@127.0.0.1" -p "${DNSPROXY_PORT}" example.com > /dev/null 2>&1; then
        echo -e "${GREEN}dnsproxy is answering on 127.0.0.1#${DNSPROXY_PORT}${NC}"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo -e "${RED}Error: dnsproxy did not answer on 127.0.0.1#${DNSPROXY_PORT}${NC}"
        echo -e "${RED}LAN DNS is down while this is broken. Check: docker logs dnsproxy${NC}"
        echo -e "${YELLOW}Bootstrap DNS (/etc/resolv.conf) must resolve the DoH hostname:${NC}"
        echo -e "${YELLOW}  cat /etc/resolv.conf && getent hosts dns11.quad9.net${NC}"
        exit 1
    fi
    sleep 3
done

echo -e "${GREEN}Removing old dnsproxy images...${NC}"
docker image prune -f >/dev/null || true

echo ""
echo -e "${GREEN}Done! DNS proxy updated successfully.${NC}"
