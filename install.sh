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
CACHE_PRESERVED=0
if [ -d "cache" ]; then
    echo "→ Preserving existing cache..."
    CACHE_PRESERVED=1
fi

# Download latest scripts (always get fresh version)
echo "→ Downloading latest scripts..."

# Download setup script
if ! curl -fsSL "$RAW_URL/$BRANCH/tools/setup-factory-vm.sh?nocache=$(date +%s)" -o setup-factory-vm.sh.tmp; then
    echo "ERROR: Failed to download setup script"
    exit 1
fi
mv setup-factory-vm.sh.tmp setup-factory-vm.sh
chmod +x setup-factory-vm.sh
sed -i 's/\r$//' setup-factory-vm.sh 2>/dev/null || dos2unix setup-factory-vm.sh 2>/dev/null || true

# Download alpine-install.exp
if ! curl -fsSL "$RAW_URL/$BRANCH/tools/alpine-install.exp?nocache=$(date +%s)" -o alpine-install.exp.tmp; then
    echo "ERROR: Failed to download alpine-install.exp"
    exit 1
fi
mv alpine-install.exp.tmp alpine-install.exp
sed -i 's/\r$//' alpine-install.exp 2>/dev/null || dos2unix alpine-install.exp 2>/dev/null || true

# Download modules archive (Phase 3.5 modular architecture)
echo "→ Downloading modules..."
mkdir -p lib

if ! curl -fsSL "$RAW_URL/$BRANCH/tools/lib/modules.ar?nocache=$(date +%s)" -o lib/modules.ar.tmp; then
    echo "ERROR: Failed to download modules archive"
    exit 1
fi
mv lib/modules.ar.tmp lib/modules.ar

# Extract modules from archive
cd lib && ar x modules.ar && cd ..
rm -f lib/modules.ar  # Clean up archive after extraction

echo "✓ Scripts and modules downloaded"

# Notify about cache preservation
if [ $CACHE_PRESERVED -eq 1 ]; then
    echo "✓ Local cache preserved and will be used"
fi

echo ""
echo "→ Starting installation..."
echo ""

# Run the setup script with --auto flag
exec ./setup-factory-vm.sh --auto
