#!/bin/bash
#
# Factory VM One-Liner Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
#

set -e

REPO_URL="https://github.com/jcgarcia/factory-vm.git"
REPO_DIR="factory-vm"

echo "Factory VM Installer"
echo "===================="
echo ""

# Check if directory exists
if [ -d "$REPO_DIR" ]; then
    echo "✓ Repository exists, updating..."
    cd "$REPO_DIR"
    git pull
else
    echo "✓ Cloning repository..."
    git clone "$REPO_URL"
    cd "$REPO_DIR"
fi

echo ""
echo "✓ Starting installation..."
echo ""

# Run the setup script with --auto flag
exec ./setup-factory-vm.sh --auto
