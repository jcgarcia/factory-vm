#!/bin/bash
################################################################################
# Factory VM - Uninstall Script
#
# Removes Factory VM installation while preserving the download cache.
#
# Usage:
#   ./uninstall-factory-vm.sh [--all]
#
# Options:
#   --all    Also remove the cache (~/.factory-vm/cache)
#
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VM_DIR="${HOME}/vms/factory"
INSTALL_DIR="${HOME}/factory-vm"
CACHE_DIR="${HOME}/.factory-vm/cache"
SCRIPTS_DIR="${HOME}/.scripts"

REMOVE_CACHE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --all)
            REMOVE_CACHE=true
            ;;
        -h|--help)
            echo "Usage: $0 [--all]"
            echo ""
            echo "Removes Factory VM installation."
            echo ""
            echo "Options:"
            echo "  --all    Also remove the download cache (~/.factory-vm/cache)"
            echo "           Without --all, cache is preserved for faster reinstall"
            echo ""
            exit 0
            ;;
    esac
done

echo ""
echo "Factory VM Uninstaller"
echo "======================"
echo ""

# 1. Stop VM if running
if [ -f "${VM_DIR}/factory.pid" ]; then
    PID=$(cat "${VM_DIR}/factory.pid" 2>/dev/null || true)
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
        echo -e "${YELLOW}Stopping running VM (PID: $PID)...${NC}"
        if [ -x "${VM_DIR}/stop-factory.sh" ]; then
            "${VM_DIR}/stop-factory.sh" || true
        else
            kill "$PID" 2>/dev/null || true
        fi
        sleep 2
    fi
fi

# 2. Remove VM files
if [ -d "$VM_DIR" ]; then
    echo -n "Removing VM files (~/${VM_DIR#$HOME/})... "
    rm -rf "$VM_DIR"
    echo -e "${GREEN}done${NC}"
else
    echo "VM directory not found (already removed)"
fi

# 3. Remove install directory
if [ -d "$INSTALL_DIR" ]; then
    echo -n "Removing install directory (~/${INSTALL_DIR#$HOME/})... "
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}done${NC}"
else
    echo "Install directory not found (already removed)"
fi

# 4. Remove symlinks in ~/.scripts/
echo -n "Removing symlinks in ~/.scripts/... "
rm -f "${SCRIPTS_DIR}/factorystart" 2>/dev/null || true
rm -f "${SCRIPTS_DIR}/factorystop" 2>/dev/null || true
rm -f "${SCRIPTS_DIR}/factorystatus" 2>/dev/null || true
rm -f "${SCRIPTS_DIR}/factorysecrets" 2>/dev/null || true
echo -e "${GREEN}done${NC}"

# 5. Remove SSH config entry (optional - leave for now as it's harmless)
# Could add: sed -i '/^Host factory$/,/^$/d' ~/.ssh/config

# 6. Handle cache
if [ "$REMOVE_CACHE" = true ]; then
    if [ -d "$CACHE_DIR" ]; then
        CACHE_SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -n "Removing cache ($CACHE_SIZE)... "
        rm -rf "${HOME}/.factory-vm"
        echo -e "${GREEN}done${NC}"
    fi
else
    if [ -d "$CACHE_DIR" ]; then
        CACHE_SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${YELLOW}Cache preserved${NC} ($CACHE_SIZE in ~/.factory-vm/cache)"
        echo "  Use --all to also remove cache"
    fi
fi

echo ""
echo -e "${GREEN}✓ Factory VM uninstalled${NC}"
echo ""
echo "To reinstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash"
echo ""
