#!/usr/bin/env bash
################################################################################
# Factory VM Clean for Testing
# 
# Cleans Factory VM installation while PRESERVING the data disk cache.
# Use this between tests to get a clean installation without losing cached
# tools, Docker images, and other downloaded artifacts.
#
# What gets deleted:
#   - VM system disk (factory.qcow2)
#   - VM configuration files
#   - SSH configuration
#   - Management scripts
#
# What gets PRESERVED:
#   - Data disk (factory-data.qcow2) - contains cache
#   - Host-side cache (~/ factory-vm/cache/)
#
# Usage:
#   ./clean-for-test.sh
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC}   $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

# Paths
VM_DIR="${HOME}/vms/factory"
DATA_DISK="${VM_DIR}/factory-data.qcow2"
SYSTEM_DISK="${VM_DIR}/factory.qcow2"
SSH_CONFIG="${HOME}/.ssh/config.d/factory"

################################################################################
# Main
################################################################################

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║        Factory VM Clean for Testing                      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

log_info "This will remove VM installation but preserve cache"
log_info ""
log_info "Will DELETE:"
log_info "  - VM system disk"
log_info "  - VM configuration"
log_info "  - SSH settings"
log_info ""
log_info "Will PRESERVE:"
log_info "  - Data disk (cache)"
log_info "  - Host cache"
echo ""

# Confirm
read -p "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Cancelled by user"
    exit 0
fi

echo ""
log "Stopping Factory VM..."

# Stop VM if running
if [ -f "${VM_DIR}/stop-factory.sh" ]; then
    "${VM_DIR}/stop-factory.sh" 2>/dev/null || true
fi

sleep 2

# Kill any lingering QEMU processes
sudo pkill -9 qemu-system-aarch64 2>/dev/null || true
sleep 2

# Free port 2222
sudo lsof -ti:2222 | xargs -r sudo kill -9 2>/dev/null || true
sleep 1

log_success "VM stopped"

# Preserve data disk if it exists
DATA_DISK_BACKUP=""
if [ -f "$DATA_DISK" ]; then
    log "Preserving data disk..."
    DATA_DISK_BACKUP="${HOME}/.factory-vm-data-backup.qcow2"
    cp "$DATA_DISK" "$DATA_DISK_BACKUP"
    log_success "Data disk backed up to: $DATA_DISK_BACKUP"
    
    # Show size
    local size=$(du -h "$DATA_DISK_BACKUP" | cut -f1)
    log_info "Data disk size: $size (contains cached tools and Docker images)"
fi

# Remove VM directory (including system disk)
if [ -d "$VM_DIR" ]; then
    log "Removing VM directory..."
    rm -rf "$VM_DIR"
    log_success "VM directory removed"
fi

# Remove SSH configuration
if [ -f "$SSH_CONFIG" ] || [ -f "${SSH_CONFIG}.conf" ]; then
    log "Removing SSH configuration..."
    rm -f "$SSH_CONFIG" "${SSH_CONFIG}.conf" "${HOME}/.ssh/config.d/factory"*
    log_success "SSH configuration removed"
fi

# Remove convenience scripts
if [ -d "${HOME}/.scripts" ]; then
    log "Removing convenience scripts..."
    rm -f "${HOME}/.scripts/factory"*
    log_success "Convenience scripts removed"
fi

echo ""
log_success "Clean complete!"
echo ""

if [ -n "$DATA_DISK_BACKUP" ]; then
    log_info "Data disk preserved at: $DATA_DISK_BACKUP"
    log_info "It will be automatically restored on next installation"
    log_info ""
    log_info "To remove data disk cache completely:"
    log_info "  rm $DATA_DISK_BACKUP"
fi

echo ""
log_info "Ready for fresh installation:"
log_info "  curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash"
echo ""
