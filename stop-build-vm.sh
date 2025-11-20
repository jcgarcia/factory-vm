#!/bin/bash

################################################################################
# Alpine ARM64 Build VM Stop Script
#
# Gracefully stops the Alpine ARM64 build VM
#
################################################################################

set -euo pipefail

VM_NAME="alpine-arm64"
VM_SSH_PORT="2222"
VM_USERNAME="alpine"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[VM-STOP]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# Check if VM is running
if ! pgrep -f "qemu-system-aarch64.*${VM_NAME}" > /dev/null 2>&1; then
    log "VM is not running"
    exit 0
fi

log "Stopping Alpine ARM64 build VM..."

# Try graceful shutdown via SSH first
if ssh -o ConnectTimeout=5 \
       -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o BatchMode=yes \
       -p "$VM_SSH_PORT" \
       "${VM_USERNAME}@localhost" \
       "sudo poweroff" &>/dev/null; then
    log "Sent shutdown command to VM..."
    
    # Wait for VM to stop (max 30 seconds)
    local count=0
    while pgrep -f "qemu-system-aarch64.*${VM_NAME}" > /dev/null 2>&1 && [ $count -lt 30 ]; do
        sleep 1
        ((count++))
    done
    
    if pgrep -f "qemu-system-aarch64.*${VM_NAME}" > /dev/null 2>&1; then
        log_warning "VM did not stop gracefully, forcing shutdown..."
        pkill -f "qemu-system-aarch64.*${VM_NAME}"
    else
        log "✓ VM stopped gracefully"
    fi
else
    log_warning "Could not connect via SSH, forcing shutdown..."
    pkill -f "qemu-system-aarch64.*${VM_NAME}"
    log "✓ VM stopped (forced)"
fi
