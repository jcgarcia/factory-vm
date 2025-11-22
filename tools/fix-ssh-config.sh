#!/bin/bash
################################################################################
# Fix SSH Config - Remove Duplicate Factory Entries
#
# This script cleans up the ~/.ssh/config file by removing all duplicate
# factory VM entries and keeping only one clean entry.
#
# Usage: bash fix-ssh-config.sh
################################################################################

set -euo pipefail

SSH_CONFIG="${HOME}/.ssh/config"
BACKUP="${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

echo "Fixing SSH config..."

# Backup current config
if [ -f "$SSH_CONFIG" ]; then
    echo "Creating backup: $BACKUP"
    cp "$SSH_CONFIG" "$BACKUP"
else
    echo "No SSH config found, nothing to fix"
    exit 0
fi

# Remove all factory-related entries using awk
echo "Removing duplicate factory entries..."
awk '
    # Skip factory-related comments
    /^# Alpine ARM64 VM - Factory Build Environment$/ { skip=1; next }
    /^# .*[Ff]actory.*/ { skip=1; next }
    
    # Skip Host factory block
    /^Host factory$/ { skip=1; next }
    
    # When we hit another Host, stop skipping
    skip==1 && /^Host / { skip=0 }
    
    # Skip indented lines while in factory block
    skip==1 && /^[[:space:]]/ { next }
    
    # Skip blank lines in factory block
    skip==1 && /^$/ { next }
    
    # Print everything else
    skip==0 { print }
' "$SSH_CONFIG" > "${SSH_CONFIG}.tmp"

# Replace original
mv "${SSH_CONFIG}.tmp" "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

echo "✓ SSH config cleaned"
echo ""
echo "Backup saved at: $BACKUP"
echo ""
echo "If you need to restore: cp $BACKUP $SSH_CONFIG"
echo ""
echo "To add factory VM entry, run factory-vm installation or manually add:"
echo ""
cat << 'EOF'
# Alpine ARM64 VM - Factory Build Environment
Host factory
    HostName localhost
    Port 2222
    User foreman
    IdentityFile /home/jcgarcia/.ssh/factory-foreman
    IdentitiesOnly yes
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
