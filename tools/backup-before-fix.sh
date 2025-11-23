#!/bin/bash
################################################################################
# Backup SSH Config and Factory VM Files
#
# Creates timestamped backups of:
# - ~/.ssh/config
# - ~/.ssh/factory-foreman key
# - ~/.factory-vm/ directory
# - ~/vms/factory/ directory (if exists)
#
# Usage: bash backup-before-fix.sh
################################################################################

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${HOME}/.factory-vm-backups/${TIMESTAMP}"

echo "================================"
echo "Factory VM Backup Utility"
echo "================================"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup SSH config
if [ -f "${HOME}/.ssh/config" ]; then
    echo "Backing up SSH config..."
    cp "${HOME}/.ssh/config" "$BACKUP_DIR/ssh-config"
    echo "✓ SSH config backed up"
else
    echo "⚠ No SSH config found"
fi

# Backup factory SSH key
if [ -f "${HOME}/.ssh/factory-foreman" ]; then
    echo "Backing up factory SSH key..."
    cp "${HOME}/.ssh/factory-foreman" "$BACKUP_DIR/factory-foreman"
    cp "${HOME}/.ssh/factory-foreman.pub" "$BACKUP_DIR/factory-foreman.pub" 2>/dev/null || true
    echo "✓ SSH key backed up"
else
    echo "⚠ No factory SSH key found"
fi

# Backup factory-vm directory
if [ -d "${HOME}/.factory-vm" ]; then
    echo "Backing up ~/.factory-vm/..."
    cp -r "${HOME}/.factory-vm" "$BACKUP_DIR/dot-factory-vm"
    echo "✓ ~/.factory-vm/ backed up"
else
    echo "⚠ No ~/.factory-vm directory found"
fi

# Backup VM directory (but not the large disk images)
if [ -d "${HOME}/vms/factory" ]; then
    echo "Backing up VM config files..."
    mkdir -p "$BACKUP_DIR/vms-factory"
    
    # Copy everything except .qcow2 files (too large)
    find "${HOME}/vms/factory" -maxdepth 1 -type f ! -name "*.qcow2" -exec cp {} "$BACKUP_DIR/vms-factory/" \; 2>/dev/null || true
    
    echo "✓ VM config files backed up (disk images excluded)"
else
    echo "⚠ No VM directory found"
fi

# Create restore script
cat > "$BACKUP_DIR/RESTORE.sh" << 'EOFSCRIPT'
#!/bin/bash
# Restore from this backup
set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Restoring from backup: $BACKUP_DIR"
echo ""

# Restore SSH config
if [ -f "$BACKUP_DIR/ssh-config" ]; then
    echo "Restoring SSH config..."
    cp "$BACKUP_DIR/ssh-config" "${HOME}/.ssh/config"
    chmod 600 "${HOME}/.ssh/config"
    echo "✓ SSH config restored"
fi

# Restore SSH key
if [ -f "$BACKUP_DIR/factory-foreman" ]; then
    echo "Restoring SSH key..."
    cp "$BACKUP_DIR/factory-foreman" "${HOME}/.ssh/factory-foreman"
    chmod 600 "${HOME}/.ssh/factory-foreman"
    [ -f "$BACKUP_DIR/factory-foreman.pub" ] && cp "$BACKUP_DIR/factory-foreman.pub" "${HOME}/.ssh/factory-foreman.pub"
    echo "✓ SSH key restored"
fi

# Restore factory-vm directory
if [ -d "$BACKUP_DIR/dot-factory-vm" ]; then
    echo "Restoring ~/.factory-vm/..."
    rm -rf "${HOME}/.factory-vm"
    cp -r "$BACKUP_DIR/dot-factory-vm" "${HOME}/.factory-vm"
    echo "✓ ~/.factory-vm/ restored"
fi

# Restore VM config
if [ -d "$BACKUP_DIR/vms-factory" ]; then
    echo "Restoring VM config files..."
    mkdir -p "${HOME}/vms/factory"
    cp "$BACKUP_DIR/vms-factory/"* "${HOME}/vms/factory/" 2>/dev/null || true
    echo "✓ VM config restored"
fi

echo ""
echo "Restore complete!"
EOFSCRIPT

chmod +x "$BACKUP_DIR/RESTORE.sh"

# Create manifest
cat > "$BACKUP_DIR/MANIFEST.txt" << EOF
Factory VM Backup
=================

Created: $(date)
Backup Directory: $BACKUP_DIR

Contents:
---------
$(ls -lh "$BACKUP_DIR")

To Restore:
-----------
cd "$BACKUP_DIR"
bash RESTORE.sh

Files Backed Up:
----------------
EOF

# List what was backed up
find "$BACKUP_DIR" -type f -name "*.sh" -o -name "*config*" -o -name "*foreman*" >> "$BACKUP_DIR/MANIFEST.txt" 2>/dev/null || true

echo ""
echo "================================"
echo "Backup Complete!"
echo "================================"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Files backed up:"
ls -lh "$BACKUP_DIR" | tail -n +2
echo ""
echo "To restore this backup:"
echo "  cd $BACKUP_DIR"
echo "  bash RESTORE.sh"
echo ""
echo "To view manifest:"
echo "  cat $BACKUP_DIR/MANIFEST.txt"
echo ""
