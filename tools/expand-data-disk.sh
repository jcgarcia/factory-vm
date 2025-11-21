#!/usr/bin/env bash
################################################################################
# Factory VM Data Disk Expansion Script
# 
# Expands the data disk for Factory VM when you need more space for builds,
# Docker images, or Jenkins artifacts.
#
# Usage:
#   ./expand-data-disk.sh [size_in_GB]
#
# Example:
#   ./expand-data-disk.sh 100   # Expand to 100GB
#   ./expand-data-disk.sh 200   # Expand to 200GB
#
# Prerequisites:
#   - Factory VM must be stopped
#   - You must have sufficient disk space on host
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
log_error() { echo -e "${RED}[ERROR]${NC}  $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

# Default paths
VM_DIR="${HOME}/vms/factory"
DATA_DISK="${VM_DIR}/factory-data.qcow2"

################################################################################
# Print usage
################################################################################

usage() {
    cat << EOF
${GREEN}Factory VM Data Disk Expansion${NC}

Usage:
  $0 <size_in_GB>

Examples:
  $0 100    # Expand data disk to 100GB
  $0 200    # Expand data disk to 200GB
  $0 500    # Expand data disk to 500GB

Current disk status:
EOF
    
    if [ -f "$DATA_DISK" ]; then
        local current_size=$(qemu-img info "$DATA_DISK" | grep "virtual size" | awk '{print $3}')
        local current_usage=$(du -h "$DATA_DISK" | cut -f1)
        echo "  Disk file: $DATA_DISK"
        echo "  Virtual size: ${current_size}"
        echo "  Actual usage: ${current_usage} (sparse file)"
    else
        echo "  ${YELLOW}Data disk not found: $DATA_DISK${NC}"
        echo "  Run setup-factory-vm.sh first to create the VM"
    fi
    
    exit 1
}

################################################################################
# Check if VM is running
################################################################################

check_vm_not_running() {
    if pgrep -f "qemu-system-aarch64.*factory.qcow2" > /dev/null; then
        log_error "Factory VM is currently running!"
        log_info "Stop the VM first: ~/vms/factory/stop-factory.sh"
        exit 1
    fi
}

################################################################################
# Expand disk
################################################################################

expand_disk() {
    local new_size="$1"
    
    log "Expanding Factory VM data disk to ${new_size}GB..."
    
    # Check if disk exists
    if [ ! -f "$DATA_DISK" ]; then
        log_error "Data disk not found: $DATA_DISK"
        log_info "Run setup-factory-vm.sh first to create the VM"
        exit 1
    fi
    
    # Check available host disk space
    local available_gb=$(df -BG "$VM_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_gb" -lt "$new_size" ]; then
        log_error "Insufficient disk space on host"
        log_info "Required: ${new_size}GB, Available: ${available_gb}GB"
        log_info "Note: QCOW2 files are sparse - they grow as needed"
        log_warning "Continuing anyway (sparse files only use actual data space)..."
    fi
    
    # Show current size
    local current_size=$(qemu-img info "$DATA_DISK" | grep "virtual size" | awk '{print $3}')
    log_info "Current virtual size: ${current_size}"
    log_info "Target size: ${new_size}GB"
    
    # Expand the disk image
    log_info "Expanding QCOW2 image (this is instant)..."
    if qemu-img resize "$DATA_DISK" "${new_size}G"; then
        log_success "Disk image expanded successfully"
    else
        log_error "Failed to expand disk image"
        exit 1
    fi
    
    # Show new size
    local new_virtual=$(qemu-img info "$DATA_DISK" | grep "virtual size" | awk '{print $3}')
    log_success "New virtual size: ${new_virtual}"
    
    log ""
    log_info "Next steps:"
    log_info "1. Start Factory VM: ~/vms/factory/start-factory.sh"
    log_info "2. Connect: ssh factory"
    log_info "3. Expand the filesystem inside VM:"
    log_info ""
    log_info "   ${BLUE}# Check current partition${NC}"
    log_info "   sudo fdisk -l /dev/vdb"
    log_info ""
    log_info "   ${BLUE}# Grow partition (if using parted)${NC}"
    log_info "   sudo parted /dev/vdb resizepart 1 100%"
    log_info ""
    log_info "   ${BLUE}# Grow filesystem (ext4)${NC}"
    log_info "   sudo resize2fs /dev/vdb1"
    log_info ""
    log_info "   ${BLUE}# OR grow filesystem (xfs)${NC}"
    log_info "   sudo xfs_growfs /data"
    log_info ""
    log_info "   ${BLUE}# Verify new size${NC}"
    log_info "   df -h /data"
    log ""
    log_success "Data disk expansion complete!"
}

################################################################################
# Main
################################################################################

main() {
    # Show header
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        Factory VM Data Disk Expansion                    ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check arguments
    if [ $# -eq 0 ]; then
        usage
    fi
    
    local new_size="$1"
    
    # Validate size is a number
    if ! [[ "$new_size" =~ ^[0-9]+$ ]]; then
        log_error "Size must be a number in GB"
        usage
    fi
    
    # Validate size is reasonable (at least 50GB, max 2TB)
    if [ "$new_size" -lt 50 ]; then
        log_error "Size must be at least 50GB"
        exit 1
    fi
    
    if [ "$new_size" -gt 2000 ]; then
        log_error "Size must be less than 2TB (2000GB)"
        exit 1
    fi
    
    # Check if qemu-img is available
    if ! command -v qemu-img >/dev/null 2>&1; then
        log_error "qemu-img not found"
        log_info "Install: sudo apt install qemu-utils"
        exit 1
    fi
    
    # Check VM is not running
    check_vm_not_running
    
    # Expand the disk
    expand_disk "$new_size"
}

main "$@"
