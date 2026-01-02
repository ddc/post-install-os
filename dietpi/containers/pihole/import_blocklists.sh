#!/usr/bin/env bash
#
# Pi-hole Blocklist Import Script
# Imports blocklist URLs from blocklists.txt into gravity.db
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKLISTS_FILE="$SCRIPT_DIR/blocklists.txt"

echo -e "${GREEN}Pi-hole Blocklist Import Script${NC}"
echo ""

# Check if container is running
if ! docker ps | grep -q pihole; then
    echo -e "${YELLOW}Error: Pi-hole container is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

# Check if blocklists.txt exists
if [ ! -f "$BLOCKLISTS_FILE" ]; then
    echo -e "${YELLOW}Error: blocklists.txt not found${NC}"
    exit 1
fi

# Install sqlite3 in container if not present (idempotent)
if ! docker exec pihole which sqlite3 >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing sqlite3 in Pi-hole container...${NC}"
    # Try apk (Alpine - Pi-hole default), then apt-get (Debian/Ubuntu)
    if docker exec pihole which apk >/dev/null 2>&1; then
        docker exec pihole apk add --no-cache sqlite
    elif docker exec pihole which apt-get >/dev/null 2>&1; then
        docker exec pihole bash -c 'apt-get update -qq && apt-get install -y sqlite3'
    else
        echo -e "${YELLOW}Error: Could not find package manager (apk or apt-get)${NC}"
        exit 1
    fi
    echo -e "${GREEN}sqlite3 installed (will remain for future use)${NC}"
    echo ""
fi

# Read desired blocklists from file into array
echo -e "${BLUE}Reading desired blocklists from: $BLOCKLISTS_FILE${NC}"
declare -a desired_urls
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Trim whitespace and add to array
    url=$(echo "$line" | xargs)
    desired_urls+=("$url")
done < "$BLOCKLISTS_FILE"

echo -e "${BLUE}Found ${#desired_urls[@]} blocklists in blocklists.txt${NC}"
echo ""

# Get current auto-imported blocklists from database
echo -e "${BLUE}Checking current Pi-hole blocklists...${NC}"
declare -a current_urls
while IFS= read -r url; do
    current_urls+=("$url")
done < <(docker exec pihole sqlite3 /etc/pihole/gravity.db \
    "SELECT address FROM adlist WHERE comment='Auto-imported from blocklists.txt';" 2>/dev/null)

echo -e "${BLUE}Found ${#current_urls[@]} auto-imported blocklists in Pi-hole${NC}"
echo ""

# Track changes
added_count=0
removed_count=0
kept_count=0

# Remove blocklists that are no longer in blocklists.txt
echo -e "${BLUE}Removing obsolete blocklists...${NC}"
for current_url in "${current_urls[@]}"; do
    found=false
    for desired_url in "${desired_urls[@]}"; do
        if [ "$current_url" = "$desired_url" ]; then
            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        docker exec pihole sqlite3 /etc/pihole/gravity.db \
            "DELETE FROM adlist WHERE address='$current_url' AND comment='Auto-imported from blocklists.txt';"
        echo -e "${YELLOW}✗${NC} Removed: $current_url"
        removed_count=$((removed_count + 1))
    fi
done

# Add new blocklists from blocklists.txt
echo -e "${BLUE}Adding new blocklists...${NC}"
for desired_url in "${desired_urls[@]}"; do
    found=false
    for current_url in "${current_urls[@]}"; do
        if [ "$current_url" = "$desired_url" ]; then
            found=true
            break
        fi
    done

    if [ "$found" = true ]; then
        echo -e "${GREEN}✓${NC} Already exists: $desired_url"
        kept_count=$((kept_count + 1))
    else
        # Check if URL exists in database with any comment (to avoid UNIQUE constraint error)
        exists=$(docker exec pihole sqlite3 /etc/pihole/gravity.db \
            "SELECT COUNT(*) FROM adlist WHERE address='$desired_url' AND type=0;" 2>/dev/null || echo "0")

        if [ "$exists" -gt 0 ]; then
            # URL exists but with different comment - update it to our management
            docker exec pihole sqlite3 /etc/pihole/gravity.db \
                "UPDATE adlist SET comment='Auto-imported from blocklists.txt', enabled=1 WHERE address='$desired_url' AND type=0;"
            echo -e "${YELLOW}↻${NC} Updated (already existed): $desired_url"
            kept_count=$((kept_count + 1))
        else
            # Insert new blocklist (type=0 for blocklist, enabled=1)
            docker exec pihole sqlite3 /etc/pihole/gravity.db \
                "INSERT INTO adlist (address, enabled, type, comment) VALUES ('$desired_url', 1, 0, 'Auto-imported from blocklists.txt');"
            echo -e "${GREEN}✓${NC} Added: $desired_url"
            added_count=$((added_count + 1))
        fi
    fi
done

echo ""
echo -e "${BLUE}Sync Summary:${NC}"
echo -e "  ${GREEN}Added:${NC} $added_count"
echo -e "  ${YELLOW}Removed:${NC} $removed_count"
echo -e "  ${BLUE}Unchanged:${NC} $kept_count"

# Update gravity if any changes were made
if [ $added_count -gt 0 ] || [ $removed_count -gt 0 ]; then
    echo ""
    echo -e "${GREEN}Updating gravity database (this may take a few minutes)...${NC}"
    docker exec pihole pihole -g
    echo ""
    echo -e "${GREEN}Done! Blocklists synced and gravity updated.${NC}"
else
    echo ""
    echo -e "${YELLOW}No changes detected. Gravity update skipped.${NC}"
fi

echo ""
echo -e "${GREEN}Blocklist sync complete!${NC}"
echo -e "${BLUE}Note: sqlite3 is kept installed for database operations${NC}"
