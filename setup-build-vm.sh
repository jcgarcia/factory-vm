#!/bin/bash

################################################################################
# Alpine ARM64 VM Setup Script
#
# This script creates and configures an Alpine Linux ARM64 virtual machine
# for building ARM-based Docker images, reducing AWS infrastructure costs.
#
# What it creates:
# - Alpine Linux ARM64 VM (via QEMU)
# - System disk (alpine-arm64.qcow2)
# - Data disk (alpine-data.qcow2)
# - SSH configuration for easy access
# - Docker and build tools inside the VM
#
# Prerequisites:
# - QEMU with ARM64 support
# - curl for downloading Alpine ISO
# - SSH client
#
# Usage:
#   ./factory-vm/setup-factory-vm.sh [--recreate] [--skip-vm-creation]
#
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DIR="${HOME}/vms"
VM_NAME="alpine-arm64"
VM_MEMORY="2G"
VM_CPUS="2"
VM_SSH_PORT="2222"
VM_USERNAME="alpine"
VM_HOSTNAME="alpine-build"

# Disk configuration
SYSTEM_DISK_SIZE="10G"
DATA_DISK_SIZE="50G"
SYSTEM_DISK="${VM_DIR}/${VM_NAME}.qcow2"
DATA_DISK="${VM_DIR}/alpine-data.qcow2"

# Alpine Linux
ALPINE_VERSION="3.19"
ALPINE_ISO="alpine-virt-${ALPINE_VERSION}.1-aarch64.iso"
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/aarch64/${ALPINE_ISO}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
RECREATE=false
SKIP_VM_CREATION=false

################################################################################
# Utility Functions
################################################################################

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"
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
# Check Prerequisites
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    
    local errors=0
    
    # Check QEMU
    if ! command -v qemu-system-aarch64 &> /dev/null; then
        log_error "qemu-system-aarch64 not found"
        log_info "Install QEMU with ARM64 support:"
        log_info "  Ubuntu/Debian: sudo apt-get install qemu-system-arm qemu-efi-aarch64"
        log_info "  macOS: brew install qemu"
        ((errors++))
    else
        log "  ✓ QEMU ARM64 available"
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log_error "curl not found"
        ((errors++))
    else
        log "  ✓ curl available"
    fi
    
    # Check SSH
    if ! command -v ssh &> /dev/null; then
        log_error "ssh not found"
        ((errors++))
    else
        log "  ✓ SSH client available"
    fi
    
    # Check for KVM support (optional, for better performance)
    if [ -e /dev/kvm ]; then
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            log "  ✓ KVM available (will use hardware acceleration)"
        else
            log_warning "KVM exists but not accessible (add user to kvm group for better performance)"
            log_info "  sudo usermod -aG kvm $USER"
        fi
    else
        log_info "  KVM not available (VM will run without hardware acceleration)"
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "$errors prerequisite(s) missing"
        exit 1
    fi
    
    log "✓ All prerequisites satisfied"
}

################################################################################
# Setup VM Directory
################################################################################

setup_vm_directory() {
    log "Setting up VM directory..."
    
    mkdir -p "${VM_DIR}"
    mkdir -p "${VM_DIR}/isos"
    mkdir -p "${VM_DIR}/docs"
    
    log "  VM directory: ${VM_DIR}"
}

################################################################################
# Download Alpine ISO
################################################################################

download_alpine_iso() {
    log "Checking Alpine Linux ISO..."
    
    local iso_path="${VM_DIR}/isos/${ALPINE_ISO}"
    
    if [ -f "$iso_path" ]; then
        log "  ✓ Alpine ISO already downloaded: $iso_path"
        return 0
    fi
    
    log "  Downloading Alpine Linux ${ALPINE_VERSION} ARM64..."
    log_info "  URL: ${ALPINE_ISO_URL}"
    
    if curl -L -o "$iso_path" "${ALPINE_ISO_URL}"; then
        log "  ✓ Alpine ISO downloaded successfully"
    else
        log_error "Failed to download Alpine ISO"
        exit 1
    fi
}

################################################################################
# Create VM Disks
################################################################################

create_vm_disks() {
    log "Creating VM disks..."
    
    # Check if disks exist
    if [ -f "$SYSTEM_DISK" ] && [ "$RECREATE" = false ]; then
        log "  ✓ System disk already exists: $SYSTEM_DISK"
    else
        if [ -f "$SYSTEM_DISK" ]; then
            log_warning "Recreating system disk (old data will be lost)"
            rm -f "$SYSTEM_DISK"
        fi
        
        log "  Creating system disk (${SYSTEM_DISK_SIZE})..."
        qemu-img create -f qcow2 "$SYSTEM_DISK" "$SYSTEM_DISK_SIZE"
        log "  ✓ System disk created"
    fi
    
    if [ -f "$DATA_DISK" ] && [ "$RECREATE" = false ]; then
        log "  ✓ Data disk already exists: $DATA_DISK"
    else
        if [ -f "$DATA_DISK" ]; then
            log_warning "Recreating data disk (old data will be lost)"
            rm -f "$DATA_DISK"
        fi
        
        log "  Creating data disk (${DATA_DISK_SIZE})..."
        qemu-img create -f qcow2 "$DATA_DISK" "$DATA_DISK_SIZE"
        log "  ✓ Data disk created"
    fi
}

################################################################################
# Generate VM Start Script
################################################################################

generate_start_script() {
    log "Generating VM start script..."
    
    local start_script="${VM_DIR}/start-alpine-vm.sh"
    
    # Determine QEMU acceleration options
    local qemu_accel=""
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        qemu_accel="-enable-kvm"
    fi
    
    cat > "$start_script" << 'SCRIPT_EOF'
#!/bin/bash

# Alpine ARM64 VM Startup Script
# This script starts the Alpine Linux ARM64 build VM

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_EOF

    cat >> "$start_script" << SCRIPT_EOF
SYSTEM_DISK="${SYSTEM_DISK}"
DATA_DISK="${DATA_DISK}"
VM_MEMORY="${VM_MEMORY}"
VM_CPUS="${VM_CPUS}"
SSH_PORT="${VM_SSH_PORT}"

# Check if VM is already running
if pgrep -f "qemu-system-aarch64.*${VM_NAME}" > /dev/null; then
    echo "VM is already running"
    echo "Connect with: ssh -p \${SSH_PORT} alpine@localhost"
    exit 0
fi

# Check disks exist
if [ ! -f "\$SYSTEM_DISK" ]; then
    echo "Error: System disk not found: \$SYSTEM_DISK"
    echo "Run setup-factory-vm.sh first"
    exit 1
fi

echo "Starting Alpine ARM64 build VM..."
echo "  Memory: \${VM_MEMORY}"
echo "  CPUs: \${VM_CPUS}"
echo "  SSH Port: \${SSH_PORT}"
echo ""
echo "Connect with: ssh -p \${SSH_PORT} ${VM_USERNAME}@localhost"
echo "Or use alias: ssh alpine-arm"
echo ""
echo "Press Ctrl+A then X to exit QEMU console"
echo ""

# Start QEMU
qemu-system-aarch64 \\
    -M virt ${qemu_accel} \\
    -cpu cortex-a72 \\
    -smp \${VM_CPUS} \\
    -m \${VM_MEMORY} \\
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd \\
    -drive file="\$SYSTEM_DISK",if=virtio,format=qcow2 \\
    -drive file="\$DATA_DISK",if=virtio,format=qcow2 \\
    -device virtio-net-pci,netdev=net0 \\
    -netdev user,id=net0,hostfwd=tcp::\${SSH_PORT}-:22 \\
    -nographic \\
    -serial mon:stdio
SCRIPT_EOF

    chmod +x "$start_script"
    
    log "  ✓ Start script created: $start_script"
}

################################################################################
# Generate Installation Script
################################################################################

generate_install_script() {
    log "Generating Alpine installation script..."
    
    local install_script="${VM_DIR}/install-alpine.sh"
    
    cat > "$install_script" << 'INSTALL_EOF'
#!/bin/bash

# Alpine Linux Installation Script for ARM64 Build VM
# Run this inside the Alpine installer

set -e

echo "Alpine Linux ARM64 Build VM Installation"
echo "========================================"
echo ""

# Setup Alpine
setup-alpine -q

# After installation completes
echo ""
echo "Installation complete!"
echo "Run: poweroff"
echo "Then restart VM without ISO to boot from disk"
INSTALL_EOF

    chmod +x "$install_script"
    
    log "  ✓ Installation script created: $install_script"
}

################################################################################
# Setup SSH Configuration
################################################################################

setup_ssh_config() {
    log "Setting up SSH configuration..."
    
    local ssh_config="${HOME}/.ssh/config"
    local ssh_config_entry="Host alpine-arm
    HostName localhost
    Port ${VM_SSH_PORT}
    User ${VM_USERNAME}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null"
    
    # Check if entry already exists
    if grep -q "Host alpine-arm" "$ssh_config" 2>/dev/null; then
        log "  ✓ SSH config entry already exists"
    else
        log "  Adding SSH config entry..."
        echo "" >> "$ssh_config"
        echo "# Alpine ARM64 Build VM" >> "$ssh_config"
        echo "$ssh_config_entry" >> "$ssh_config"
        log "  ✓ SSH config updated"
    fi
    
    log "  You can now connect with: ssh alpine-arm"
}

################################################################################
# Generate VM Setup Documentation
################################################################################

generate_documentation() {
    log "Generating documentation..."
    
    local doc_file="${VM_DIR}/docs/README.md"
    
    cat > "$doc_file" << 'DOC_EOF'
# Alpine ARM64 Build VM

This directory contains the Alpine Linux ARM64 virtual machine used for building ARM-based Docker images for the FinTech application.

## Why ARM64?

Building and deploying ARM64 images reduces AWS infrastructure costs by ~30-40% compared to x86_64:
- AWS Graviton instances are cheaper
- Better performance per dollar
- Lower energy consumption

## VM Details

- **OS**: Alpine Linux 3.19 (ARM64)
- **Memory**: 2GB (configurable)
- **CPUs**: 2 cores (configurable)
- **Disks**:
  - System disk: 10GB (alpine-arm64.qcow2)
  - Data disk: 50GB (alpine-data.qcow2)
- **SSH Port**: 2222

## Files

- `alpine-arm64.qcow2` - System disk
- `alpine-data.qcow2` - Data disk (Docker images, build cache)
- `start-alpine-vm.sh` - Start the VM
- `install-alpine.sh` - Installation helper script
- `isos/` - Alpine Linux ISO images

## Usage

### Start VM

```bash
./start-alpine-vm.sh
```

### Connect to VM

```bash
# Using SSH alias
ssh alpine-arm

# Or directly
ssh -p 2222 alpine@localhost
```

### Stop VM

Inside VM:
```bash
sudo poweroff
```

Or from host (QEMU console): Press `Ctrl+A` then `X`

### Build Docker Images in VM

```bash
# Connect to VM
ssh alpine-arm

# Navigate to mounted project
cd /mnt/project

# Build ARM64 image
docker build -t fintech-backend:arm64 -f backend/Dockerfile .

# Save image for transfer
docker save fintech-backend:arm64 | gzip > fintech-backend-arm64.tar.gz
```

## Inside the VM

The VM has the following pre-installed:
- Docker (for building ARM64 images)
- Git
- Node.js and npm (for backend builds)
- Build essentials (gcc, make, etc.)

## Troubleshooting

### VM won't start

Check if QEMU is installed:
```bash
qemu-system-aarch64 --version
```

### Can't connect via SSH

Check VM is running:
```bash
pgrep -f qemu-system-aarch64
```

Check SSH port:
```bash
netstat -ln | grep 2222
```

### Slow performance

Add your user to the KVM group for hardware acceleration:
```bash
sudo usermod -aG kvm $USER
# Logout and login again
```

## Maintenance

### Update Alpine packages

```bash
ssh alpine-arm
sudo apk update
sudo apk upgrade
```

### Clean Docker cache

```bash
ssh alpine-arm
docker system prune -af
```

### Expand data disk

```bash
# On host
qemu-img resize ~/vms/alpine-data.qcow2 +20G

# Inside VM
sudo growpart /dev/vdb 1
sudo resize2fs /dev/vdb1
```
DOC_EOF

    log "  ✓ Documentation created: $doc_file"
}

################################################################################
# Display Next Steps
################################################################################

display_next_steps() {
    cat << 'NEXT_STEPS'

╔═══════════════════════════════════════════════════════════╗
║        Alpine ARM64 Build VM Setup Complete               ║
╚═══════════════════════════════════════════════════════════╝

VM Files Location: ~/vms/

Next Steps:

1. Start the VM (first time - install Alpine):
   cd ~/vms
   ./start-alpine-vm.sh

2. Inside Alpine installer, run:
   setup-alpine
   
   Configure:
   - Keyboard: us
   - Hostname: alpine-build
   - Network: eth0 (dhcp)
   - Root password: <set a password>
   - Timezone: <your timezone>
   - Proxy: none
   - Mirror: f (fastest)
   - SSH: openssh
   - Disk: sys (install to /dev/vda)
   - Disk: /dev/vda (use entire disk)

3. After installation, poweroff:
   poweroff

4. Restart VM:
   ./start-alpine-vm.sh

5. Connect and configure:
   ssh alpine-arm
   
   # Install Docker and tools
   sudo apk add docker docker-compose git nodejs npm
   sudo rc-update add docker boot
   sudo service docker start
   sudo addgroup alpine docker

6. Test Docker:
   docker run --rm arm64v8/alpine uname -m
   # Should output: aarch64

Ready to build ARM images!

Documentation: ~/vms/docs/README.md

NEXT_STEPS
}

################################################################################
# Main
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --recreate)
                RECREATE=true
                shift
                ;;
            --skip-vm-creation)
                SKIP_VM_CREATION=true
                shift
                ;;
            -h|--help)
                cat << 'HELP'
Alpine ARM64 Build VM Setup Script

Creates and configures an Alpine Linux ARM64 virtual machine for building
ARM-based Docker images, reducing AWS infrastructure costs.

Usage:
  ./factory-vm/setup-factory-vm.sh [OPTIONS]

Options:
  --recreate              Recreate VM disks (destroys existing data)
  --skip-vm-creation      Skip VM creation (only setup scripts)
  -h, --help             Show this help message

Examples:
  # Initial setup
  ./factory-vm/setup-factory-vm.sh

  # Recreate VM from scratch
  ./factory-vm/setup-factory-vm.sh --recreate

  # Only update scripts
  ./factory-vm/setup-factory-vm.sh --skip-vm-creation

HELP
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    cat << 'BANNER'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        Alpine ARM64 Build VM Setup                       ║
║                                                           ║
║  Creates ARM64 VM for building cost-optimized Docker     ║
║  images for AWS Graviton instances                       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

BANNER

    check_prerequisites
    setup_vm_directory
    
    if [ "$SKIP_VM_CREATION" = false ]; then
        download_alpine_iso
        create_vm_disks
    fi
    
    generate_start_script
    generate_install_script
    setup_ssh_config
    generate_documentation
    
    log ""
    log "✓ VM setup complete!"
    log ""
    
    display_next_steps
}

# Run main
main "$@"
