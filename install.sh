#!/bin/bash
#
# Factory VM One-Liner Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
# Version: 2.0.0
#

set -e

REPO_URL="https://github.com/jcgarcia/factory-vm.git"
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

# Check if directory exists
if [ -d "$REPO_DIR" ]; then
    echo "→ Repository exists, checking for updates..."
    cd "$REPO_DIR"
    
    # Get current branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Get local and remote commit hashes
    local_commit=$(git rev-parse HEAD)
    
    # Fetch latest from remote
    git fetch origin "$BRANCH" --quiet 2>/dev/null || {
        echo "⚠ Warning: Could not fetch updates (offline?)"
        echo "→ Using existing local version"
        echo ""
    }
    
    remote_commit=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "$local_commit")
    
    if [ "$local_commit" == "$remote_commit" ]; then
        echo "✓ Repository is up to date!"
        echo "  Local:  $local_commit"
        echo "  Remote: $remote_commit"
    else
        echo "→ Updates available!"
        echo "  Local:  $local_commit"
        echo "  Remote: $remote_commit"
        echo ""
        echo "→ Pulling latest changes..."
        
        # Switch to branch if needed
        if [ "$current_branch" != "$BRANCH" ]; then
            git checkout "$BRANCH" --quiet
        fi
        
        # Stash any local changes to cache
        if ! git diff --quiet || ! git diff --cached --quiet; then
            echo "→ Preserving local cache..."
            git stash --quiet
        fi
        
        # Pull updates
        git pull origin "$BRANCH" --quiet
        
        echo "✓ Repository updated!"
    fi
else
    echo "→ Cloning repository..."
    git clone -b "$BRANCH" "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
    echo "✓ Repository cloned"
fi

echo ""
echo "→ Starting installation..."
echo ""

# Run the setup script with --auto flag
exec ./setup-factory-vm.sh --auto
