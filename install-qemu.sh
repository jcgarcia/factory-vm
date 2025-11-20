#!/bin/bash

################################################################################
# QEMU Installation Script
#
# Installs QEMU with ARM64 support for building ARM Docker images
#
# Supports:
#   - Ubuntu/Debian
#   - macOS (via Homebrew)
#   - Fedora/RHEL
#
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[QEMU-INSTALL]${NC} $*"
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
# Detect OS
################################################################################

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            OS_VERSION=$VERSION_ID
        else
            log_error "Cannot detect Linux distribution"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        log_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
    
    log "Detected OS: $OS"
}

################################################################################
# Install QEMU on Ubuntu/Debian
################################################################################

install_ubuntu() {
    log "Installing QEMU on Ubuntu/Debian..."
    
    sudo apt-get update
    
    # Install QEMU packages
    sudo apt-get install -y \
        qemu-system-arm \
        qemu-efi-aarch64 \
        qemu-utils \
        qemu-system-gui
    
    # Optional: KVM for hardware acceleration
    if [ -e /dev/kvm ]; then
        log_info "Installing KVM support..."
        sudo apt-get install -y qemu-kvm libvirt-daemon-system
        
        # Add user to kvm group
        if ! groups | grep -q kvm; then
            log_info "Adding $USER to kvm group..."
            sudo usermod -aG kvm "$USER"
            log_warning "You need to logout and login again for KVM access"
        fi
    fi
    
    log "✓ QEMU installed successfully"
}

################################################################################
# Install QEMU on Fedora/RHEL
################################################################################

install_fedora() {
    log "Installing QEMU on Fedora/RHEL..."
    
    sudo dnf install -y \
        qemu-system-aarch64 \
        qemu-img \
        edk2-aarch64
    
    # Optional: KVM
    if [ -e /dev/kvm ]; then
        sudo dnf install -y qemu-kvm libvirt
        
        if ! groups | grep -q kvm; then
            sudo usermod -aG kvm "$USER"
            log_warning "You need to logout and login again for KVM access"
        fi
    fi
    
    log "✓ QEMU installed successfully"
}

################################################################################
# Install QEMU on macOS
################################################################################

install_macos() {
    log "Installing QEMU on macOS..."
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew is required but not installed"
        log_info "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    # Install QEMU
    brew install qemu
    
    log "✓ QEMU installed successfully"
    log_info "Note: macOS doesn't support KVM acceleration"
}

################################################################################
# Verify Installation
################################################################################

verify_installation() {
    log "Verifying QEMU installation..."
    
    if ! command -v qemu-system-aarch64 &> /dev/null; then
        log_error "qemu-system-aarch64 not found in PATH"
        exit 1
    fi
    
    local version=$(qemu-system-aarch64 --version | head -1)
    log "✓ $version"
    
    # Check for UEFI firmware
    local firmware_paths=(
        "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
        "/usr/share/edk2/aarch64/QEMU_EFI.fd"
        "/usr/share/AAVMF/AAVMF_CODE.fd"
        "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    )
    
    local firmware_found=false
    for path in "${firmware_paths[@]}"; do
        if [ -f "$path" ]; then
            log "✓ UEFI firmware found: $path"
            firmware_found=true
            break
        fi
    done
    
    if [ "$firmware_found" = false ]; then
        log_warning "UEFI firmware not found, VM may not boot"
        log_info "You may need to install edk2-aarch64 or qemu-efi-aarch64 package"
    fi
    
    # Check KVM
    if [ -e /dev/kvm ]; then
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            log "✓ KVM available and accessible (hardware acceleration enabled)"
        else
            log_warning "KVM exists but not accessible"
            log_info "Add yourself to kvm group: sudo usermod -aG kvm $USER"
        fi
    else
        log_info "KVM not available (VM will run without hardware acceleration)"
    fi
}

################################################################################
# Main
################################################################################

main() {
    cat << 'BANNER'
╔═══════════════════════════════════════════════════════════╗
║        QEMU ARM64 Installation                           ║
╚═══════════════════════════════════════════════════════════╝

BANNER

    # Check if already installed
    if command -v qemu-system-aarch64 &> /dev/null; then
        log "QEMU is already installed"
        verify_installation
        exit 0
    fi
    
    detect_os
    
    case "$OS" in
        ubuntu|debian)
            install_ubuntu
            ;;
        fedora|rhel|centos)
            install_fedora
            ;;
        macos)
            install_macos
            ;;
        *)
            log_error "Unsupported distribution: $OS"
            log_info "Please install QEMU manually:"
            log_info "  - qemu-system-aarch64"
            log_info "  - qemu-efi-aarch64 (or edk2-aarch64)"
            exit 1
            ;;
    esac
    
    verify_installation
    
    log ""
    log "✓ QEMU installation complete!"
    log ""
    log "Next steps:"
    log "  1. If you added to kvm group, logout and login again"
    log "  2. Run: ./factory-vm/setup-factory-vm.sh --automated"
    log ""
}

main "$@"
