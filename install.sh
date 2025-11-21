#!/bin/bash
#
# Factory VM One-Liner Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
# Version: 2.1.0
#

set -e

REPO_URL="https://github.com/jcgarcia/factory-vm.git"
RAW_URL="https://raw.githubusercontent.com/jcgarcia/factory-vm"
REPO_DIR="$HOME/factory-vm"
BRANCH="${FACTORY_VM_BRANCH:-main}"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║        Factory VM One-Liner Installer                    ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Branch: $BRANCH"
echo ""

# Create directory structure
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Preserve existing cache
if [ -d "cache" ]; then
    echo "→ Preserving existing cache..."
fi

# Download latest setup script
echo "→ Downloading latest setup script..."
if curl -fsSL "$RAW_URL/$BRANCH/setup-factory-vm.sh" -o setup-factory-vm.sh.tmp; then
    mv setup-factory-vm.sh.tmp setup-factory-vm.sh
    chmod +x setup-factory-vm.sh
    
    # Fix line endings
    sed -i 's/\r$//' setup-factory-vm.sh 2>/dev/null || dos2unix setup-factory-vm.sh 2>/dev/null || true
    
    echo "✓ Setup script downloaded"
else
    echo "ERROR: Failed to download setup script"
    exit 1
fi

echo ""
echo "→ Starting installation..."
echo ""

# Run the setup script with --auto flag
exec ./setup-factory-vm.sh --auto
