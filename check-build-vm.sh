#!/bin/bash

################################################################################
# Alpine ARM64 Build VM Health Check Script
#
# Checks if the build VM is properly configured, running, and accessible.
# Used by readiness.sh to verify build infrastructure.
#
# Exit codes:
#   0 - VM is ready
#   1 - VM not configured
#   2 - VM not running
#   3 - VM not accessible (SSH)
#
################################################################################

set -euo pipefail

# Configuration
VM_DIR="${HOME}/vms"
VM_NAME="alpine-arm64"
VM_SSH_PORT="2222"
VM_USERNAME="alpine"
SYSTEM_DISK="${VM_DIR}/${VM_NAME}.qcow2"
DATA_DISK="${VM_DIR}/alpine-data.qcow2"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[VM-CHECK]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

################################################################################
# Check VM Configuration
################################################################################

check_vm_configured() {
    log "Checking VM configuration..."
    
    # Check if VM directory exists
    if [ ! -d "$VM_DIR" ]; then
        log_error "VM directory not found: $VM_DIR"
        log_info "Run: ./factory-vm/setup-factory-vm.sh"
        return 1
    fi
    
    # Check if disks exist
    if [ ! -f "$SYSTEM_DISK" ]; then
        log_error "System disk not found: $SYSTEM_DISK"
        log_info "Run: ./factory-vm/setup-factory-vm.sh"
        return 1
    fi
    
    if [ ! -f "$DATA_DISK" ]; then
        log_warning "Data disk not found: $DATA_DISK"
        log_info "Run: ./factory-vm/setup-factory-vm.sh"
        return 1
    fi
    
    # Check if start script exists
    if [ ! -f "${VM_DIR}/start-alpine-vm.sh" ]; then
        log_error "VM start script not found"
        log_info "Run: ./factory-vm/setup-factory-vm.sh"
        return 1
    fi
    
    log "  ✓ VM is configured"
    return 0
}

################################################################################
# Check VM Running
################################################################################

check_vm_running() {
    log "Checking if VM is running..."
    
    if pgrep -f "qemu-system-aarch64.*${VM_NAME}" > /dev/null 2>&1; then
        log "  ✓ VM is running"
        return 0
    else
        log_warning "VM is not running"
        log_info "Start with: cd ~/vms && ./start-alpine-vm.sh"
        return 2
    fi
}

################################################################################
# Check SSH Access
################################################################################

check_ssh_access() {
    log "Checking SSH access..."
    
    # Wait a moment for SSH to be ready
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o BatchMode=yes \
               -p "$VM_SSH_PORT" \
               "${VM_USERNAME}@localhost" \
               "exit" &>/dev/null; then
            log "  ✓ SSH access working"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_info "  Retry $attempt/$max_attempts..."
            sleep 2
        fi
        
        ((attempt++))
    done
    
    log_error "Cannot connect to VM via SSH"
    log_info "Check VM console for errors"
    return 3
}

################################################################################
# Check Docker in VM
################################################################################

check_docker_in_vm() {
    log "Checking Docker in VM..."
    
    if ssh -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o BatchMode=yes \
           -p "$VM_SSH_PORT" \
           "${VM_USERNAME}@localhost" \
           "docker --version" &>/dev/null; then
        local docker_version=$(ssh -o ConnectTimeout=5 \
                                   -o StrictHostKeyChecking=no \
                                   -o UserKnownHostsFile=/dev/null \
                                   -o BatchMode=yes \
                                   -p "$VM_SSH_PORT" \
                                   "${VM_USERNAME}@localhost" \
                                   "docker --version" 2>/dev/null)
        log "  ✓ Docker available: $docker_version"
        return 0
    else
        log_warning "Docker not installed in VM"
        log_info "Install with: ssh alpine-arm 'sudo apk add docker && sudo rc-update add docker boot && sudo service docker start'"
        return 1
    fi
}

################################################################################
# Check VM Architecture
################################################################################

check_vm_architecture() {
    log "Checking VM architecture..."
    
    local arch=$(ssh -o ConnectTimeout=5 \
                     -o StrictHostKeyChecking=no \
                     -o UserKnownHostsFile=/dev/null \
                     -o BatchMode=yes \
                     -p "$VM_SSH_PORT" \
                     "${VM_USERNAME}@localhost" \
                     "uname -m" 2>/dev/null)
    
    if [ "$arch" = "aarch64" ]; then
        log "  ✓ VM is ARM64 (aarch64)"
        return 0
    else
        log_error "VM architecture is not ARM64: $arch"
        return 1
    fi
}

################################################################################
# Full Health Check
################################################################################

full_health_check() {
    local status=0
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║        Alpine ARM64 Build VM Health Check                ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Configuration check
    if ! check_vm_configured; then
        return 1
    fi
    
    # Running check
    if ! check_vm_running; then
        return 2
    fi
    
    # SSH check
    if ! check_ssh_access; then
        return 3
    fi
    
    # Docker check (warning only, not critical)
    check_docker_in_vm || status=4
    
    # Architecture check
    check_vm_architecture || return 5
    
    echo ""
    if [ $status -eq 0 ]; then
        log "✓ VM is fully operational and ready for ARM64 builds"
    elif [ $status -eq 4 ]; then
        log_warning "VM is operational but Docker needs configuration"
    fi
    echo ""
    
    return $status
}

################################################################################
# Quick Check (for readiness.sh)
################################################################################

quick_check() {
    # Just check if configured and running
    check_vm_configured &>/dev/null || return 1
    check_vm_running &>/dev/null || return 2
    check_ssh_access &>/dev/null || return 3
    return 0
}

################################################################################
# Display VM Status
################################################################################

display_status() {
    echo ""
    echo "VM Status:"
    echo "  Location: $VM_DIR"
    echo "  System Disk: $SYSTEM_DISK"
    echo "  Data Disk: $DATA_DISK"
    
    if pgrep -f "qemu-system-aarch64.*${VM_NAME}" > /dev/null 2>&1; then
        local pid=$(pgrep -f "qemu-system-aarch64.*${VM_NAME}")
        echo "  Running: Yes (PID: $pid)"
        echo "  SSH: ssh alpine-arm (or ssh -p $VM_SSH_PORT ${VM_USERNAME}@localhost)"
    else
        echo "  Running: No"
        echo "  Start: cd ~/vms && ./start-alpine-vm.sh"
    fi
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    case "${1:-full}" in
        --quick)
            # Quick check for automation
            quick_check
            exit $?
            ;;
        --status)
            # Just display status
            display_status
            exit 0
            ;;
        --full|*)
            # Full health check
            full_health_check
            local result=$?
            display_status
            exit $result
            ;;
    esac
}

main "$@"
