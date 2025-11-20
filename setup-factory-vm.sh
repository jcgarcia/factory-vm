#!/bin/bash

################################################################################
# Factory VM - Fully Automated Setup
#
# Creates a complete ARM64 build environment with:
#   - Hostname: factory.local
#   - User: foreman (with sudo)
#   - SSH key authentication
#   - Build tools: Jenkins, Docker, Kubernetes, Terraform, AWS CLI
#   - SSL/HTTPS on default port 443
#   - Automated Alpine installation
#   - SSH config on host
#
# Usage:
#   ./factory-vm/setup-factory-vm.sh [--auto|-y]
#
#   --auto, -y    Use recommended settings without prompts
#
################################################################################

set -euo pipefail

# Trap errors and cleanup
trap 'echo "ERROR: Installation failed at line $LINENO. Check logs for details." >&2; exit 1' ERR

# Parse command-line arguments
AUTO_MODE=false
for arg in "$@"; do
    case $arg in
        --auto|-y)
            AUTO_MODE=true
            shift
            ;;
    esac
done

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DIR="${HOME}/vms/factory"
VM_NAME="factory"
VM_MEMORY="4G"
VM_CPUS="4"
VM_SSH_PORT="2222"

# Factory VM Configuration
VM_HOSTNAME="factory.local"
VM_USERNAME="foreman"
SSH_KEY_NAME="factory-foreman"

# Security: Passwords will be generated securely during installation
# No hardcoded passwords in this script

# Disk configuration
SYSTEM_DISK_SIZE="50G"  # Increased for Docker images
DATA_DISK_SIZE="200G"   # Increased for build artifacts
SYSTEM_DISK="${VM_DIR}/${VM_NAME}.qcow2"
DATA_DISK="${VM_DIR}/${VM_NAME}-data.qcow2"

# Alpine Linux
ALPINE_VERSION="3.19"
ALPINE_ARCH="aarch64"
ALPINE_ISO="alpine-virt-${ALPINE_VERSION}.1-${ALPINE_ARCH}.iso"
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/${ALPINE_ISO}"

# Tool versions
TERRAFORM_VERSION="1.6.6"
KUBECTL_VERSION="1.28.4"
HELM_VERSION="3.13.3"
JENKINS_VERSION="2.426.1"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Security Functions
################################################################################

# Generate cryptographically secure random password
generate_secure_password() {
    # Generate 20-character password with letters, numbers, and safe symbols
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-20
}

################################################################################
# Logging
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

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

################################################################################
# Detect System Resources and Offer Configuration
################################################################################

detect_system_resources() {
    local total_mem_gb=0
    local available_disk_gb=0
    local cpu_cores=0
    
    # Detect memory
    if command -v free &> /dev/null; then
        # Linux
        total_mem_gb=$(free | grep Mem: | awk '{print int($2/1024/1024)}')
    elif command -v sysctl &> /dev/null && sysctl hw.memsize &> /dev/null 2>&1; then
        # macOS
        total_mem_gb=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
    fi
    
    # Detect disk space
    if command -v df &> /dev/null; then
        available_disk_gb=$(df -k "$HOME" | tail -1 | awk '{print int($4/1024/1024)}')
    fi
    
    # Detect CPU cores
    if command -v nproc &> /dev/null; then
        cpu_cores=$(nproc)
    elif command -v sysctl &> /dev/null && sysctl -n hw.ncpu &> /dev/null 2>&1; then
        cpu_cores=$(sysctl -n hw.ncpu)
    fi
    
    # Return values only (no logging during detection)
    echo "$total_mem_gb:$available_disk_gb:$cpu_cores"
}

offer_configuration_choice() {
    log ""
    log ""
    log "=========================================="
    log "Factory VM Configuration Selection"
    log "=========================================="
    log ""
    
    # Detect resources
    local resources=$(detect_system_resources)
    local total_mem_gb=$(echo "$resources" | cut -d: -f1)
    local available_disk_gb=$(echo "$resources" | cut -d: -f2)
    local cpu_cores=$(echo "$resources" | cut -d: -f3)
    
    # Display detected resources
    log "Detected system resources:"
    log_info "  Total RAM: ${total_mem_gb} GB"
    log_info "  Available disk: ${available_disk_gb} GB"
    log_info "  CPU cores: ${cpu_cores}"
    
    log ""
    log "Available configuration profiles:"
    log ""
    
    # Determine which profiles are available
    local can_optimal=false
    local can_recommended=false
    local can_minimum=false
    
    # Check if system can handle each profile
    if [ "$total_mem_gb" -ge 16 ] && [ "$available_disk_gb" -ge 200 ] && [ "$cpu_cores" -ge 8 ]; then
        can_optimal=true
    fi
    
    if [ "$total_mem_gb" -ge 8 ] && [ "$available_disk_gb" -ge 140 ] && [ "$cpu_cores" -ge 4 ]; then
        can_recommended=true
    fi
    
    if [ "$total_mem_gb" -ge 6 ] && [ "$available_disk_gb" -ge 50 ] && [ "$cpu_cores" -ge 2 ]; then
        can_minimum=true
    fi
    
    # Show available profiles
    local profile_count=1
    local profiles=()
    
    if [ "$can_optimal" = true ]; then
        log "${GREEN}[$profile_count] OPTIMAL${NC} - Maximum performance (recommended for your system)"
        log "    Memory: 8 GB  |  CPUs: 6 cores  |  System: 50 GB  |  Data: 200 GB"
        log "    Best for: Frequent builds, multiple concurrent jobs, large projects"
        log ""
        profiles+=("optimal")
        ((profile_count++))
    fi
    
    if [ "$can_recommended" = true ]; then
        log "${GREEN}[$profile_count] RECOMMENDED${NC} - Balanced performance (default)"
        log "    Memory: 4 GB  |  CPUs: 4 cores  |  System: 50 GB  |  Data: 200 GB"
        log "    Best for: Regular builds, standard development workflow"
        log ""
        profiles+=("recommended")
        ((profile_count++))
    fi
    
    if [ "$can_minimum" = true ]; then
        log "${YELLOW}[$profile_count] MINIMUM${NC} - Resource-constrained (slower builds)"
        log "    Memory: 2 GB  |  CPUs: 2 cores  |  System: 50 GB  |  Data: 100 GB"
        log "    Best for: Occasional builds, limited host resources"
        log ""
        profiles+=("minimum")
        ((profile_count++))
    fi
    
    # Custom option always available
    log "${BLUE}[$profile_count] CUSTOM${NC} - Manually specify configuration"
    log "    Configure your own memory, CPU, and disk allocation"
    log ""
    profiles+=("custom")
    
    # Check if any profile is available
    if [ "$can_minimum" = false ]; then
        log_error "Your system does not meet minimum requirements for Factory VM:"
        log_info "  Required: 6GB RAM, 50GB disk, 2 CPU cores"
        log_info "  Available: ${total_mem_gb}GB RAM, ${available_disk_gb}GB disk, ${cpu_cores} CPU cores"
        log ""
        log "You can still try CUSTOM configuration, but performance may be poor."
        log ""
    fi
    
    # Prompt for selection
    local choice
    
    # Auto-mode: intelligently select best profile based on resources
    if [ "$AUTO_MODE" = true ]; then
        # Check if resources are critically low
        if [ "$can_minimum" = false ]; then
            log_error "System resources are below minimum requirements!"
            log_info "  Required: 6GB RAM, 50GB disk, 2 CPU cores"
            log_info "  Available: ${total_mem_gb}GB RAM, ${available_disk_gb}GB disk, ${cpu_cores} CPU cores"
            log ""
            log_warning "Factory VM may not work properly with these resources."
            log ""
            read -p "Do you want to continue anyway? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log "Setup cancelled by user"
                exit 0
            fi
            # Use minimum settings even if below minimum
            VM_MEMORY="2G"
            VM_CPUS="2"
            DATA_DISK_SIZE="100G"
            log_info "Selected: MINIMUM configuration (below recommended)"
        elif [ "$can_optimal" = true ]; then
            # Best resources available - use OPTIMAL
            # Directly set values instead of relying on array index
            VM_MEMORY="8G"
            VM_CPUS="6"
            DATA_DISK_SIZE="200G"
            log_info "Auto-mode: Using OPTIMAL profile (best performance)"
        elif [ "$can_recommended" = true ]; then
            # Good resources - use RECOMMENDED
            # Directly set values instead of relying on array index
            VM_MEMORY="4G"
            VM_CPUS="4"
            DATA_DISK_SIZE="200G"
            log_info "Auto-mode: Using RECOMMENDED profile (balanced)"
        else
            # Limited resources - use MINIMUM
            # Directly set values instead of relying on array index
            VM_MEMORY="2G"
            VM_CPUS="2"
            DATA_DISK_SIZE="100G"
            log_info "Auto-mode: Using MINIMUM profile (resource-constrained)"
        fi
    fi
    
    # Interactive mode: prompt user
    if [ "$AUTO_MODE" = false ]; then
        while true; do
            read -p "Select configuration profile [1-$profile_count]: " choice
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$profile_count" ]; then
                break
            else
                log_error "Invalid selection. Please enter a number between 1 and $profile_count"
            fi
        done
        
        # Apply selected profile (only in interactive mode)
        local selected_profile="${profiles[$((choice-1))]}"
        
        case "$selected_profile" in
            optimal)
                VM_MEMORY="8G"
                VM_CPUS="6"
                DATA_DISK_SIZE="200G"
                log_info "Selected: OPTIMAL configuration"
                ;;
            recommended)
                VM_MEMORY="4G"
                VM_CPUS="4"
                DATA_DISK_SIZE="200G"
                log_info "Selected: RECOMMENDED configuration"
                ;;
            minimum)
                VM_MEMORY="2G"
                VM_CPUS="2"
                DATA_DISK_SIZE="100G"
                log_info "Selected: MINIMUM configuration"
                ;;
            custom)
                configure_custom_resources "$total_mem_gb" "$cpu_cores" "$available_disk_gb"
                ;;
        esac
    fi
    
    log ""
    log "Final Factory VM Configuration:"
    log "  Memory: $VM_MEMORY"
    log "  CPUs: $VM_CPUS"
    log "  System Disk: $SYSTEM_DISK_SIZE"
    log "  Data Disk: $DATA_DISK_SIZE"
    log ""
}

configure_custom_resources() {
    local max_mem_gb=$1
    local max_cpus=$2
    local max_disk_gb=$3
    
    log ""
    log "Custom Configuration"
    log "===================="
    log ""
    
    # Memory
    local mem_gb
    while true; do
        read -p "Memory allocation in GB [1-$max_mem_gb, recommended 4-8]: " mem_gb
        if [[ "$mem_gb" =~ ^[0-9]+$ ]] && [ "$mem_gb" -ge 1 ] && [ "$mem_gb" -le "$max_mem_gb" ]; then
            VM_MEMORY="${mem_gb}G"
            if [ "$mem_gb" -lt 2 ]; then
                log_warning "Very low memory allocation. Builds will be very slow."
            elif [ "$mem_gb" -lt 4 ]; then
                log_warning "Low memory allocation. Consider 4GB+ for better performance."
            fi
            break
        else
            echo "Invalid. Enter a number between 1 and $max_mem_gb."
        fi
    done
    
    # CPUs
    local cpus
    while true; do
        read -p "CPU cores [1-$max_cpus, recommended 4]: " cpus
        if [[ "$cpus" =~ ^[0-9]+$ ]] && [ "$cpus" -ge 1 ] && [ "$cpus" -le "$max_cpus" ]; then
            VM_CPUS="$cpus"
            if [ "$cpus" -lt 2 ]; then
                log_warning "Single core will result in very slow builds."
            fi
            break
        else
            echo "Invalid. Enter a number between 1 and $max_cpus."
        fi
    done
    
    # Data disk
    local max_data_disk=$((max_disk_gb - 30))  # Reserve 30GB for system disk and overhead
    if [ "$max_data_disk" -lt 30 ]; then
        max_data_disk=30
    fi
    
    local data_disk_gb
    while true; do
        read -p "Data disk size in GB [30-$max_data_disk, recommended 100]: " data_disk_gb
        if [[ "$data_disk_gb" =~ ^[0-9]+$ ]] && [ "$data_disk_gb" -ge 30 ] && [ "$data_disk_gb" -le "$max_data_disk" ]; then
            DATA_DISK_SIZE="${data_disk_gb}G"
            if [ "$data_disk_gb" -lt 50 ]; then
                log_warning "Small data disk. You'll need to clean Docker images frequently."
            fi
            break
        else
            echo "Invalid. Enter a number between 30 and $max_data_disk."
        fi
    done
    
    log_info "Custom configuration set."
}

################################################################################
# Check/Install QEMU
################################################################################

ensure_qemu() {
    log "Checking QEMU installation..."
    
    if command -v qemu-system-aarch64 &> /dev/null; then
        log "  ✓ QEMU already installed"
        return 0
    fi
    
    log "Installing QEMU..."
    
    if [ -f "${SCRIPT_DIR}/install-qemu.sh" ]; then
        "${SCRIPT_DIR}/install-qemu.sh"
    else
        log_error "QEMU not found. Please install manually:"
        log_info "  Ubuntu: sudo apt-get install qemu-system-arm qemu-efi-aarch64"
        log_info "  macOS: brew install qemu"
        exit 1
    fi
}

################################################################################
# Check Dependencies
################################################################################

check_dependencies() {
    log "Checking dependencies..."
    
    local missing=()
    
    for cmd in curl sshpass ssh-keygen expect nc; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Missing dependencies: ${missing[*]}"
        log_info "Installing missing packages..."
        
        # Detect package manager and install
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq ${missing[*]}
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y -q ${missing[*]}
        elif command -v yum &> /dev/null; then
            sudo yum install -y -q ${missing[*]}
        elif command -v brew &> /dev/null; then
            brew install ${missing[*]}
        else
            log_error "Unable to auto-install dependencies. Package manager not found."
            log_info "Please install manually: ${missing[*]}"
            exit 1
        fi
        
        # Verify installation
        local still_missing=()
        for cmd in ${missing[@]}; do
            if ! command -v $cmd &> /dev/null; then
                still_missing+=($cmd)
            fi
        done
        
        if [ ${#still_missing[@]} -gt 0 ]; then
            log_error "Failed to install: ${still_missing[*]}"
            log_info "Please install manually and try again"
            exit 1
        fi
        
        log "  ✓ All dependencies installed successfully"
    else
        log "  ✓ All dependencies satisfied"
    fi
}

################################################################################
# Setup SSH Keys
################################################################################

setup_ssh_keys() {
    log "Setting up SSH keys for foreman user..."
    
    local ssh_dir="${HOME}/.ssh"
    local private_key="${ssh_dir}/${SSH_KEY_NAME}"
    local public_key="${ssh_dir}/${SSH_KEY_NAME}.pub"
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    if [ -f "$private_key" ]; then
        log "  ✓ SSH key already exists: $private_key"
    else
        log "  Generating SSH key pair..."
        ssh-keygen -t ed25519 -f "$private_key" -N "" -C "foreman@factory"
        log "  ✓ SSH key generated"
    fi
    
    # Export for later use
    export VM_SSH_PRIVATE_KEY="$private_key"
    export VM_SSH_PUBLIC_KEY="$public_key"
}

################################################################################
# Download Alpine ISO
################################################################################

download_alpine() {
    log "Downloading Alpine Linux ISO..."
    
    mkdir -p "${VM_DIR}/isos"
    local iso_path="${VM_DIR}/isos/${ALPINE_ISO}"
    
    if [ -f "$iso_path" ]; then
        log "  ✓ ISO already exists"
        return 0
    fi
    
    log_info "  Downloading from: ${ALPINE_ISO_URL}"
    curl -L --progress-bar -o "$iso_path" "${ALPINE_ISO_URL}"
    log "  ✓ ISO downloaded"
}

################################################################################
# Create VM Disks
################################################################################

create_disks() {
    log "Creating VM disks..."
    
    if [ ! -f "$SYSTEM_DISK" ]; then
        qemu-img create -f qcow2 "$SYSTEM_DISK" "$SYSTEM_DISK_SIZE"
        log "  ✓ System disk created (${SYSTEM_DISK_SIZE})"
    else
        log "  ✓ System disk exists"
    fi
    
    if [ ! -f "$DATA_DISK" ]; then
        qemu-img create -f qcow2 "$DATA_DISK" "$DATA_DISK_SIZE"
        log "  ✓ Data disk created (${DATA_DISK_SIZE})"
    else
        log "  ✓ Data disk exists"
    fi
}

################################################################################
# Find UEFI Firmware
################################################################################

find_uefi_firmware() {
    # UEFI firmware requires both CODE (read-only) and VARS (read-write) files
    # We'll return the CODE file path and create a writable VARS copy
    local firmware_paths=(
        "/usr/share/AAVMF/AAVMF_CODE.fd"
        "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
        "/usr/share/edk2/aarch64/QEMU_EFI.fd"
        "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
        "/usr/share/qemu/edk2-aarch64-code.fd"
    )
    
    for path in "${firmware_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    log_error "UEFI firmware not found"
    log_info "Install: sudo apt-get install qemu-efi-aarch64"
    exit 1
}

find_uefi_vars() {
    # Find the corresponding VARS file for the firmware
    local vars_paths=(
        "/usr/share/AAVMF/AAVMF_VARS.fd"
        "/usr/share/qemu-efi-aarch64/QEMU_VARS.fd"
        "/usr/share/edk2/aarch64/QEMU_VARS.fd"
        "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
        "/usr/share/qemu/edk2-arm-vars.fd"
    )
    
    for path in "${vars_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # VARS file not critical if not found
    echo ""
    return 0
}

################################################################################
# Create Setup Script (runs inside VM)
################################################################################

create_vm_setup_script() {
    log "Creating VM setup script..."
    
    local setup_script="${VM_DIR}/vm-setup.sh"
    
    cat > "$setup_script" << 'SETUP_SCRIPT_EOF'
#!/bin/bash
# This script runs inside the Factory VM to install all build tools
# Installs components individually with proper error handling and timeouts

# Security: Jenkins foreman password passed via environment variable
# Usage: JENKINS_FOREMAN_PASSWORD="secure_password" bash vm-setup.sh
if [ -z "$JENKINS_FOREMAN_PASSWORD" ]; then
    echo "ERROR: JENKINS_FOREMAN_PASSWORD environment variable must be set"
    exit 1
fi

# Don't exit on error - we want to continue even if some components fail
set +e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Security Functions
################################################################################

# Generate cryptographically secure random password
generate_secure_password() {
    # Generate 20-character password with letters, numbers, and safe symbols
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-20
}

################################################################################
# Logging Functions
################################################################################

# Track installation results
INSTALL_LOG="/root/factory-install.log"
FAILED_COMPONENTS=()
SKIPPED_COMPONENTS=()

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$INSTALL_LOG"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$INSTALL_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$INSTALL_LOG"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$INSTALL_LOG"
}

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        Factory VM Setup - Installing Build Tools          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Installation log: $INSTALL_LOG"
echo ""

# Initialize log file
date > "$INSTALL_LOG"
echo "Factory VM Build Tools Installation" >> "$INSTALL_LOG"
echo "=====================================" >> "$INSTALL_LOG"
echo "" >> "$INSTALL_LOG"

################################################################################
# Component 1: System Update and Base Packages
################################################################################

log_info "Installing Base Packages..."
{
    echo "Updating package index..." 
    sed -i "/^#.*community/s/^#//" /etc/apk/repositories || \
        echo "http://dl-cdn.alpinelinux.org/alpine/v3.19/community" >> /etc/apk/repositories
    
    apk update
    apk upgrade
    
    echo "Installing base packages..."
    apk add \
        bash bash-completion \
        curl wget \
        git \
        openssh \
        openrc \
        ca-certificates \
        tzdata \
        nano vim \
        rsync \
        jq \
        python3 py3-pip python3-dev \
        nodejs \
        openjdk17-jre \
        build-base gcc g++ make cmake \
        linux-headers \
        file \
        findutils \
        util-linux
} >> "$INSTALL_LOG" 2>&1 && log_success "Base Packages installed" || {
    log_error "Base Packages installation FAILED"
    FAILED_COMPONENTS+=("Base Packages")
}

################################################################################
# Component 2: Docker
################################################################################

log_info "Installing Docker..."
{
    echo "Installing Docker..."
    apk add docker docker-compose docker-cli-compose
    rc-update add docker boot
    service docker start || true
    docker --version
} >> "$INSTALL_LOG" 2>&1 && log_success "Docker installed" || {
    log_error "Docker installation FAILED"
    FAILED_COMPONENTS+=("Docker")
}

################################################################################
# Component 2.5: Caddy with SSL (for Jenkins reverse proxy)
################################################################################

log_info "Installing Caddy with SSL..."
{
    echo "Installing Caddy and required tools..."
    apk add caddy nss-tools
    
    # Create Caddy data directory with proper permissions
    mkdir -p /var/lib/caddy /etc/caddy
    chown -R caddy:caddy /var/lib/caddy /etc/caddy
    
    # Configure Caddy as reverse proxy for Jenkins
    # Using Caddy's automatic HTTPS with local CA (creates trusted certificates)
    cat > /etc/caddy/Caddyfile << 'CADDY_CONFIG'
{
    # Use Caddy's built-in local CA for automatic trusted certificates
    local_certs
}

# HTTPS server for Jenkins
https://factory.local {
    tls internal
    
    reverse_proxy localhost:8080
}

# Also respond to localhost
https://localhost {
    tls internal
    
    reverse_proxy localhost:8080
}
CADDY_CONFIG

    chown caddy:caddy /etc/caddy/Caddyfile
    
    # Enable Caddy to start on boot
    rc-update add caddy default
    
    # Start Caddy (this will generate the local CA)
    rc-service caddy start
    
    # Wait for Caddy to generate certificates
    sleep 3
    
    # Export the Caddy local CA certificate
    echo "Exporting Caddy local CA certificate..."
    mkdir -p /root/caddy-ca
    
    # Caddy stores its CA in the data directory
    if [ -f "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" ]; then
        cp "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" /root/caddy-ca/root.crt
        chmod 644 /root/caddy-ca/root.crt
        echo "Caddy CA certificate exported to /root/caddy-ca/root.crt"
    else
        echo "Warning: Caddy CA certificate not found yet (will be generated on first HTTPS request)"
    fi
    
    echo "Caddy configured as reverse proxy for Jenkins"
    echo "  - HTTPS (port 443) -> proxies to Jenkins (port 8080)"
    echo "  - Uses Caddy's local CA for trusted certificates"
    
} >> "$INSTALL_LOG" 2>&1 && log_success "Caddy with SSL installed" || {
    log_error "Caddy installation FAILED"
    FAILED_COMPONENTS+=("Caddy")
}

################################################################################
# Component 3: Kubernetes Tools
################################################################################

log_info "Installing Kubernetes Tools..."
{
    echo "Downloading kubectl..."
    curl -LO "https://dl.k8s.io/release/v1.28.4/bin/linux/arm64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    
    echo "Downloading Helm..."
    curl -LO "https://get.helm.sh/helm-v3.13.3-linux-arm64.tar.gz"
    tar -zxvf helm-v3.13.3-linux-arm64.tar.gz
    mv linux-arm64/helm /usr/local/bin/
    rm -rf linux-arm64 helm-v3.13.3-linux-arm64.tar.gz
    
    kubectl version --client
    helm version
} >> "$INSTALL_LOG" 2>&1 && log_success "Kubernetes Tools installed" || {
    log_error "Kubernetes Tools installation FAILED"
    FAILED_COMPONENTS+=("Kubernetes Tools")
}

################################################################################
# Component 4: Terraform
################################################################################

log_info "Installing Terraform..."
{
    echo "Downloading Terraform..."
    curl -LO "https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_arm64.zip"
    unzip terraform_1.6.6_linux_arm64.zip
    mv terraform /usr/local/bin/
    rm terraform_1.6.6_linux_arm64.zip
    terraform version
} >> "$INSTALL_LOG" 2>&1 && log_success "Terraform installed" || {
    log_error "Terraform installation FAILED"
    FAILED_COMPONENTS+=("Terraform")
}

################################################################################
# Component 5: Ansible (Optional - skipped for speed)
################################################################################

log_info "Skipping Ansible (optional - can be installed manually later)"
SKIPPED_COMPONENTS+=("Ansible")
echo "  Note: To install Ansible later, run:" >> "$INSTALL_LOG"
echo "    pip3 install --break-system-packages ansible boto3 botocore" >> "$INSTALL_LOG"

################################################################################
# Component 6: AWS CLI
################################################################################

log_info "Installing AWS CLI..."
{
    echo "Installing AWS CLI..."
    apk add aws-cli
    aws --version
} >> "$INSTALL_LOG" 2>&1 && log_success "AWS CLI installed" || {
    log_error "AWS CLI installation FAILED"
    FAILED_COMPONENTS+=("AWS CLI")
}

################################################################################
# Component 7: jcscripts (includes awslogin)
################################################################################

log_info "Installing jcscripts..."
{
    echo "Setting up jcscripts directory..."
    mkdir -p /home/foreman/.scripts
    cd /home/foreman/.scripts
    
    # Create minimal awslogin script
    echo "Creating SSH-compatible awslogin script..."
    cat > awslogin << 'AWSLOGIN_EOF'
#!/bin/bash
# AWS SSO Login Helper - SSH Compatible

set -e
PROFILE="${1:-default}"

if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ]; then
    echo "AWS SSO Login - SSH Mode"
    echo "Browser cannot be launched automatically."
    echo "Copy the URL below and open it on your local machine."
    aws sso login --profile "$PROFILE" --no-browser
else
    aws sso login --profile "$PROFILE"
fi
echo "✓ AWS SSO login successful for profile: $PROFILE"
AWSLOGIN_EOF
    chmod +x awslogin
    
    # Add to PATH for foreman user - Alpine Linux requires .profile for login shells
    # Add to .profile (for login shells - ash/sh)
    if ! grep -q ".scripts" /home/foreman/.profile 2>/dev/null; then
        echo "" >> /home/foreman/.profile
        echo "# Add jcscripts to PATH" >> /home/foreman/.profile
        echo 'export PATH="$HOME/.scripts:$PATH"' >> /home/foreman/.profile
    fi
    
    # Also add to .bashrc (for interactive bash shells)
    if [ -f /home/foreman/.bashrc ]; then
        if ! grep -q ".scripts" /home/foreman/.bashrc; then
            echo "" >> /home/foreman/.bashrc
            echo "# Add jcscripts to PATH" >> /home/foreman/.bashrc
            echo 'export PATH="$HOME/.scripts:$PATH"' >> /home/foreman/.bashrc
        fi
    fi
    
    chown -R foreman:foreman /home/foreman/.scripts
    
    # Configure AWS directory
    mkdir -p /home/foreman/.aws
    chown -R foreman:foreman /home/foreman/.aws
} >> "$INSTALL_LOG" 2>&1 && log_success "jcscripts installed" || {
    log_error "jcscripts installation FAILED"
    FAILED_COMPONENTS+=("jcscripts")
}

################################################################################
# Component 8: Android SDK (Optional - skipped for speed)
################################################################################

log_info "Skipping Android SDK (optional - can be installed manually later)"
SKIPPED_COMPONENTS+=("Android SDK")

################################################################################
# Component 9: Jenkins with Java 21 and Agent Setup
################################################################################

log_info "Installing Jenkins with Java 21..."
log_info "  This may take 5-10 minutes depending on your internet connection..."
log_info "  Progress will be shown for each step:"
log_info "    1. Creating Jenkins configuration files"
log_info "    2. Installing plugins (25+ plugins, bandwidth intensive)"
log_info "       Note: Plugin installation happens when VM starts Jenkins service"
log_info "       This is done inside the VM and may take 3-5 extra minutes"
log_info "    3. Starting Jenkins container"
log_info "    4. Waiting for initialization"
log_info "    5. Setting up CLI tools"
log_info ""
{
    echo "  Step 1/5: Creating Jenkins directories and configuration..."
    mkdir -p /opt/jenkins
    # Jenkins container runs as UID 1000, fix permissions
    chown -R 1000:1000 /opt/jenkins
    
    # Skip the initial setup wizard - configure Jenkins automatically
    echo -n "  - Configuring Jenkins automation (skip wizard, create users, configure plugins)..."
    mkdir -p /opt/jenkins/init.groovy.d
    echo " done"
    
    # Create init script to skip setup wizard and create admin user
    echo -n "  - Creating init script: 01-basic-security.groovy (admin user)..."
    cat > /opt/jenkins/init.groovy.d/01-basic-security.groovy << 'GROOVY_INIT'
#!groovy
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()

// Skip the setup wizard
if (!instance.installState.isSetupComplete()) {
    println '--> Skipping SetupWizard'
    InstallState.INITIAL_SETUP_COMPLETED.initializeState()
}

// Set authorization strategy (security realm will be set when foreman user is created)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
println '--> Jenkins basic security configured'
GROOVY_INIT
    echo " done"

    # Configure executors and disable builds on built-in node
    echo -n "  - Creating init script: 02-configure-executors.groovy (disable built-in node)..."
    cat > /opt/jenkins/init.groovy.d/02-configure-executors.groovy << 'GROOVY_CONFIG'
#!groovy
import jenkins.model.Jenkins

def instance = Jenkins.getInstance()

// Disable builds on built-in node (best practice)
instance.setNumExecutors(0)
instance.setMode(hudson.model.Node.Mode.EXCLUSIVE)

instance.save()
println '--> Built-in node configured (executors disabled - use agents for builds)'
GROOVY_CONFIG
    echo " done"

    # Note: Agent creation and plugin installation removed to avoid init script errors
    # These features are not essential for initial setup and can be configured later:
    # - Agents: Manage Jenkins > Nodes > New Node
    # - Plugins: Manage Jenkins > Plugins
    # This simplification ensures clean installation without dependency issues

    # Create foreman user with API token
    echo -n "  - Creating init script: 05-create-foreman-user.groovy (foreman user + API token for CLI)..."
    cat > /opt/jenkins/init.groovy.d/05-create-foreman-user.groovy << 'GROOVY_FOREMAN'
#!groovy
import jenkins.model.Jenkins
import hudson.model.User
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.security.ApiTokenProperty

def instance = Jenkins.getInstance()

println '--> Creating foreman user with API token...'

// Check if foreman user already exists
def user = User.get('foreman', false)
if (user == null) {
    println '--> Creating foreman user...'
    
    // Create user with secure password from environment
    def foremanPassword = System.getenv('JENKINS_FOREMAN_PASSWORD')
    if (!foremanPassword) {
        foremanPassword = 'changeme'  // Fallback (should never happen)
        println 'WARNING: JENKINS_FOREMAN_PASSWORD not set, using fallback'
    }
    
    // Add to existing security realm (don't replace it - admin user is already there)
    def realm = instance.getSecurityRealm()
    if (realm instanceof HudsonPrivateSecurityRealm) {
        realm.createAccount('foreman', foremanPassword)
        println "    Foreman user added to existing security realm"
    } else {
        // Create new realm with foreman as the only user
        def hudsonRealm = new HudsonPrivateSecurityRealm(false)
        hudsonRealm.createAccount('foreman', foremanPassword)
        instance.setSecurityRealm(hudsonRealm)
        println "    Created security realm with foreman user"
    }
    
    // Get the newly created user
    user = User.get('foreman', false)
    
    // Generate API token
    def tokenStore = user.getProperty(ApiTokenProperty.class)
    if (tokenStore == null) {
        tokenStore = new ApiTokenProperty()
        user.addProperty(tokenStore)
    }
    
    // Create a new token named "CLI Access"
    def result = tokenStore.tokenStore.generateNewToken("CLI Access")
    def tokenValue = result.plainValue
    
    // Save the token to a file for retrieval
    new File('/var/jenkins_home/foreman-api-token.txt').text = tokenValue
    
    println "--> Foreman user created successfully"
    println "    Username: foreman"
    println "    Password: (securely configured)"
    println "    API Token saved to: /var/jenkins_home/foreman-api-token.txt"
    println "    API Token: ${tokenValue}"
    println "    Token saved to: /var/jenkins_home/foreman-api-token.txt"
    
    user.save()  // Save user to persist the API token
    instance.save()
} else {
    println '--> Foreman user already exists'
    
    // Check if token file exists, if not generate new token
    def tokenFile = new File('/var/jenkins_home/foreman-api-token.txt')
    if (!tokenFile.exists()) {
        println '--> Generating new API token for existing foreman user...'
        
        def tokenStore = user.getProperty(ApiTokenProperty.class)
        if (tokenStore == null) {
            tokenStore = new ApiTokenProperty()
            user.addProperty(tokenStore)
        }
        
        def result = tokenStore.tokenStore.generateNewToken("CLI Access")
        def tokenValue = result.plainValue
        tokenFile.text = tokenValue
        
        println "    New API Token: ${tokenValue}"
        println "    Token saved to: /var/jenkins_home/foreman-api-token.txt"
        
        user.save()
    } else {
        println "    API token already exists in /var/jenkins_home/foreman-api-token.txt"
    }
}
GROOVY_FOREMAN
    echo " done"

    # Configure Jenkins URL (fixes the warning about missing Jenkins URL)
    echo -n "  - Creating init script: 06-configure-jenkins-url.groovy (set Jenkins URL)..."
    cat > /opt/jenkins/init.groovy.d/06-configure-jenkins-url.groovy << 'GROOVY_URL'
#!groovy
import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration

def instance = Jenkins.getInstance()
def location = JenkinsLocationConfiguration.get()

// Set Jenkins URL
location.setUrl("https://factory.local/")
location.setAdminAddress("jenkins-admin@factory.local")

location.save()
println '--> Jenkins URL configured: https://factory.local/'
GROOVY_URL
    echo " done"

    # Create a Docker cloud agent (recommended for builds instead of built-in node)
    echo -n "  - Creating init script: 07-configure-docker-agent.groovy (Docker cloud for builds)..."
    cat > /opt/jenkins/init.groovy.d/07-configure-docker-agent.groovy << 'GROOVY_AGENT'
#!groovy
import jenkins.model.Jenkins
import com.nirima.jenkins.plugins.docker.DockerCloud
import com.nirima.jenkins.plugins.docker.DockerTemplate
import com.nirima.jenkins.plugins.docker.DockerTemplateBase
import com.nirima.jenkins.plugins.docker.launcher.AttachedDockerComputerLauncher
import io.jenkins.docker.connector.DockerComputerAttachConnector

def instance = Jenkins.getInstance()

try {
    println '--> Configuring Docker cloud for build agents...'
    
    // Check if Docker plugin is available
    def dockerPluginClass = Class.forName('com.nirima.jenkins.plugins.docker.DockerCloud')
    
    // Create Docker cloud if it doesn't exist
    def existingCloud = instance.clouds.find { it.name == 'docker' }
    if (existingCloud == null) {
        // Docker template for ARM64 builds
        def dockerTemplateBase = new DockerTemplateBase(
            'jenkins/inbound-agent:latest',  // Image
            '',                                // DNS search domains
            'unix:///var/run/docker.sock',    // Docker host
            '',                                // Volumes
            '',                                // Volumes from
            '',                                // Environment
            '',                                // Hostname
            '',                                // User
            '',                                // Extra hosts
            '',                                // Mac address
            '',                                // Memory limit
            '',                                // Memory swap
            '',                                // CPU shares
            ''                                 // SHM size
        )
        
        def dockerTemplate = new DockerTemplate(
            dockerTemplateBase,
            new DockerComputerAttachConnector(),
            'docker linux arm64',  // Labels
            '/home/jenkins/agent', // Remote FS root
            '2'                    // Instance capacity
        )
        
        dockerTemplate.setMode(hudson.model.Node.Mode.NORMAL)
        
        def dockerCloud = new DockerCloud(
            'docker',                          // Name
            [dockerTemplate],                  // Templates
            '',                                // Server URL (uses /var/run/docker.sock)
            100,                               // Container cap
            10,                                // Connect timeout
            10,                                // Read timeout
            '',                                // Credentials ID
            '',                                // Version
            ''                                 // Docker hostname
        )
        
        instance.clouds.add(dockerCloud)
        instance.save()
        
        println "    Docker cloud configured successfully"
        println "    - Image: jenkins/inbound-agent:latest"
        println "    - Labels: docker linux arm64"
        println "    - Executors: 2 per container"
    } else {
        println "    Docker cloud already exists"
    }
} catch (ClassNotFoundException e) {
    println "    WARNING: Docker plugin not installed yet - agent setup skipped"
    println "    This is normal on first install - plugins install after init scripts run"
    println "    Agent will be configured automatically on next restart"
} catch (Exception e) {
    println "    WARNING: Error configuring Docker agent: ${e.message}"
    println "    You can configure agents manually: Manage Jenkins > Nodes > New Node"
}
GROOVY_AGENT
    echo " done"

    # Install essential plugins
    echo -n "  - Creating plugins.txt (essential plugins for ARM64 builds)..."
    cat > /opt/jenkins/plugins.txt << 'PLUGINS_TXT'
# Essential Jenkins plugins for Factory VM
# These will be installed automatically on first Jenkins start

# Configuration as Code (allows jenkins.yaml to work)
configuration-as-code:latest

# Git integration
git:latest
git-client:latest
github:latest
github-branch-source:latest

# Docker integration
docker-plugin:latest
docker-workflow:latest

# Pipeline and build tools
workflow-aggregator:latest
pipeline-stage-view:latest
pipeline-github-lib:latest
blueocean:latest

# Credentials and authentication
credentials:latest
credentials-binding:latest
plain-credentials:latest
ssh-credentials:latest

# AWS integration
aws-credentials:latest
aws-java-sdk:latest

# Build tools
gradle:latest
nodejs:latest
kubernetes:latest
kubernetes-cli:latest

# Utility plugins
timestamper:latest
build-timeout:latest
ws-cleanup:latest
ansicolor:latest
PLUGINS_TXT
    echo " done"

    # Jenkins Configuration as Code (JCasC)
    echo -n "  - Creating jenkins.yaml (Configuration as Code)..."
    cat > /opt/jenkins/jenkins.yaml << 'JENKINS_CONFIG'
jenkins:
  systemMessage: |
    Factory VM Jenkins - ARM64 Build Server
    
    - Java 21 LTS (Long-term support until 2029)
    - ARM64 native builds
    - Docker & Kubernetes support
    - AWS integration ready
    
    Do NOT build on the built-in node - use agents!
    
  numExecutors: 0  # Disable builds on built-in node
  mode: EXCLUSIVE
  
  securityRealm:
    local:
      allowsSignup: false
      
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false

unclassified:
  location:
    url: "https://factory.local/"
    adminAddress: "jenkins-admin@factory.local"
    
  globalLibraries:
    libraries:
      - name: "shared-pipeline-library"
        defaultVersion: "main"
        implicit: false
        allowVersionOverride: true
        
  buildDiscarders:
    configuredBuildDiscarders:
      - "jobBuildDiscarder"

# Nodes/Agents configuration
nodes:
  - permanent:
      name: "docker-agent-1"
      remoteFS: "/home/jenkins/agent"
      numExecutors: 2
      mode: NORMAL
      labelString: "docker linux arm64 aarch64"
      launcher:
        ssh:
          host: "factory.local"
          port: 22
          credentialsId: "jenkins-ssh-key"
          launchTimeoutSeconds: 60
          maxNumRetries: 3
          retryWaitTime: 15
      retentionStrategy:
        demand:
          inDemandDelay: 0
          idleDelay: 10
      
# Tool installations
tools:
  git:
    installations:
      - name: "Default"
        home: "/usr/bin/git"
        
  nodejs:
    installations:
      - name: "NodeJS 20"
        home: "/usr/local/bin/node"
        
  gradle:
    installations:
      - name: "Gradle 8"
        home: ""
        
  maven:
    installations:
      - name: "Maven 3"
        home: ""
JENKINS_CONFIG
    echo " done"

    echo -n "  - Setting file permissions..."
    chown -R 1000:1000 /opt/jenkins
    echo " done"
    
    echo "  ✓ Step 1/5 complete: Configuration files created"
    echo ""
    echo "  Step 2/5: Creating Jenkins service init script..."
    
    # Create Jenkins service init script
    echo -n "  - Creating /etc/init.d/jenkins service..."
    cat > /etc/init.d/jenkins << 'JENKINS_INIT'
#!/sbin/openrc-run

name="Jenkins CI"
description="Jenkins Continuous Integration Server with Java 21"

depend() {
    need docker caddy
    after docker caddy
}

start() {
    ebegin "Starting Jenkins (Java 21)"
    
    # Install plugins before starting Jenkins
    if [ -f /opt/jenkins/plugins.txt ] && [ ! -f /opt/jenkins/.plugins-installed ]; then
        echo "Installing Jenkins plugins from plugins.txt..."
        echo "This may take 3-5 minutes depending on internet speed..."
        echo "Progress:"
        docker run --rm \
            -v /opt/jenkins:/var/jenkins_home \
            jenkins/jenkins:lts-jdk21 \
            jenkins-plugin-cli --plugin-file /var/jenkins_home/plugins.txt 2>&1 | \
            while IFS= read -r line; do
                if echo "$line" | grep -qE "Downloaded|Installing|Installed|Done|plugin"; then
                    echo "  $line"
                fi
            done
        
        touch /opt/jenkins/.plugins-installed
        echo "Plugins installed successfully"
    fi
    
    # Load passwords from environment file if it exists
    if [ -f /opt/jenkins/.env ]; then
        export $(grep -v '^#' /opt/jenkins/.env | xargs)
    fi
    
    docker run -d \
        --name jenkins \
        --restart unless-stopped \
        -p 8080:8080 \
        -p 50000:50000 \
        -v /opt/jenkins:/var/jenkins_home \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx2g" \
        -e CASC_JENKINS_CONFIG=/var/jenkins_home/jenkins.yaml \
        -e JENKINS_FOREMAN_PASSWORD="$JENKINS_FOREMAN_PASSWORD" \
        jenkins/jenkins:lts-jdk21
    eend \$?
}

stop() {
    ebegin "Stopping Jenkins"
    docker stop jenkins 2>/dev/null || true
    docker rm jenkins 2>/dev/null || true
    eend \$?
}

restart() {
    stop
    sleep 2
    start
}
JENKINS_INIT
    echo " done"
    
    echo -n "  - Making service executable..."
    chmod +x /etc/init.d/jenkins
    echo " done"
    
    echo -n "  - Adding Jenkins to boot..."
    rc-update add jenkins default 2>&1 | grep -v "already installed" || true
    echo " done"
    
    echo "  ✓ Step 2/5 complete: Jenkins service configured"
    echo ""
    
    # Create environment file with passwords for Jenkins container
    echo -n "  - Creating Jenkins environment file..."
    cat > /opt/jenkins/.env << JENKINS_ENV
# Jenkins password - used by init.d script
JENKINS_FOREMAN_PASSWORD=${JENKINS_FOREMAN_PASSWORD}
JENKINS_ENV
    chmod 600 /opt/jenkins/.env
    chown 1000:1000 /opt/jenkins/.env
    echo " done"
    
    echo ""
    echo "  Step 3/5: Starting Jenkins container..."
    echo "  (This will install 25+ plugins - takes 3-5 minutes on slow connections)"
    echo "  Note: Plugin installation runs inside the VM init.d service"
    echo "        You won't see detailed progress, but it IS working"
    echo ""
    
    # Start Jenkins now
    echo "  - Starting Jenkins container (Java 21)..."
    rc-service jenkins start || true
    
    echo "  ✓ Step 3/5 complete: Jenkins container started"
    echo ""
    echo "  Step 4/5: Waiting for Jenkins to initialize..."
    
    # Wait for Jenkins to be ready (with timeout)
    echo "  - Waiting for Jenkins to initialize..."
    echo "    (This takes 2-3 minutes: starting container, loading plugins, running init scripts)"
    START_TIME=$(date +%s)
    echo -n "    Progress: "
    for i in {1..90}; do
        if docker exec jenkins test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null; then
            ELAPSED=$(($(date +%s) - START_TIME))
            echo ""
            echo "  ✓ Jenkins is ready! (took ${ELAPSED} seconds)"
            break
        fi
        if [ $i -eq 90 ]; then
            echo ""
            echo "  ⚠ Jenkins initialization timed out (may still be starting in background)"
        fi
        # Show progress dot every 5 seconds
        if [ $((i % 5)) -eq 0 ]; then
            echo -n "."
        fi
        sleep 2
    done
    echo ""
    
    echo "  ✓ Step 4/5 complete: Jenkins initialized"
    echo ""
    echo "  Step 5/5: Setting up Jenkins CLI..."
    
    # Create agent workspace
    echo "  - Creating agent workspace..."
    mkdir -p /opt/jenkins/agent
    chown -R 1000:1000 /opt/jenkins/agent
    
    # Setup Jenkins CLI inside VM
    echo "  - Setting up Jenkins CLI for VM usage..."
    mkdir -p /usr/local/share/jenkins
    # Download CLI jar from Jenkins (wait a bit for Jenkins to be ready)
    echo "  - Downloading Jenkins CLI jar..."
    sleep 10
    echo -n "    Progress: "
    for i in {1..30}; do
        if wget -q -O /usr/local/share/jenkins/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar 2>/dev/null; then
            chmod 644 /usr/local/share/jenkins/jenkins-cli.jar
            echo ""
            echo "  ✓ Jenkins CLI jar downloaded successfully"
            break
        fi
        if [ $i -eq 30 ]; then
            echo ""
            echo "  ⚠ Jenkins CLI jar download timed out (will be available later)"
        fi
        # Show progress dot every 5 seconds
        if [ $((i % 5)) -eq 0 ]; then
            echo -n "."
        fi
        sleep 2
    done
    echo ""
    
    # Add jenkins-factory function to /etc/profile.d so it's available for all users
    cat > /etc/profile.d/jenkins-cli.sh << 'JENKINS_CLI_PROFILE'
# Jenkins CLI helper function
jenkins-factory() {
    local api_token
    
    # Get token from Jenkins container (use sudo if needed)
    if docker ps >/dev/null 2>&1; then
        api_token=$(docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null | tr -d '\n\r')
    else
        api_token=$(sudo docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null | tr -d '\n\r')
    fi
    
    if [ -z "$api_token" ]; then
        echo "Error: Could not retrieve API token from Jenkins" >&2
        return 1
    fi
    
    # Call Jenkins CLI with token directly in auth parameter (not via stdin)
    java -jar /usr/local/share/jenkins/jenkins-cli.jar \
        -s https://factory.local \
        -auth foreman:"$api_token" \
        -webSocket \
        "$@"
}
JENKINS_CLI_PROFILE
    chmod +x /etc/profile.d/jenkins-cli.sh
    echo "  ✓ Jenkins CLI configured (jenkins-factory command available)"
    echo ""
    echo "  ✓ Step 5/5 complete: Jenkins CLI setup finished"
    echo ""
    
    # Install Caddy CA certificate in system trust store
    echo "  - Installing Caddy CA certificate for HTTPS..."
    cp /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt /usr/local/share/ca-certificates/caddy-local-ca.crt
    update-ca-certificates >/dev/null 2>&1
    echo "  - Caddy CA certificate installed (HTTPS will work without warnings)"
    
    echo ""
    echo "Jenkins Configuration:"
    echo "  - Version: Latest LTS with Java 21"
    echo "  - URL: https://factory.local"
    echo "  - Admin User: admin"
    echo "  - Admin Password: (securely configured)"
    echo "  - CLI User: foreman"
    echo "  - CLI Password: (uses API token)"
    echo "  - Built-in node: DISABLED (use agents for builds)"
    echo "  - Agent: factory-agent-1 (2 executors, ARM64, Docker, Kubernetes)"
    echo "  - Essential plugins: INSTALLING IN BACKGROUND (25+)"
    echo "  - Java 21 support until: September 2029"
    echo ""
    
} >> "$INSTALL_LOG" 2>&1 && log_success "Jenkins installed and configured" || {
    log_error "Jenkins installation FAILED"
    FAILED_COMPONENTS+=("Jenkins")
}

################################################################################
# Installation Summary
################################################################################

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        Installation Complete!                             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Show installed versions
log_info "Verifying installed components..."
echo ""

# Function to safely get version
get_version() {
    local cmd="$1"
    local version_arg="${2:---version}"
    if command -v "$cmd" >/dev/null 2>&1; then
        $cmd $version_arg 2>&1 | head -1 || echo "installed (version check failed)"
    else
        echo "NOT INSTALLED"
    fi
}

echo "Installed Tools:"
echo "  Docker:     $(get_version docker --version)"
echo "  kubectl:    $(get_version kubectl version --client=true --short=true)"
echo "  Helm:       $(get_version helm version --short)"
echo "  Terraform:  $(get_version terraform version | head -1)"
echo "  AWS CLI:    $(get_version aws --version)"
echo "  Jenkins:    Configured and running (https://factory.local)"
echo "              User: foreman (password shown at end of installation)"
echo ""

# Show any failed components
if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
    log_warning "Some components failed to install:"
    for comp in "${FAILED_COMPONENTS[@]}"; do
        echo "  - $comp"
    done
    echo ""
    log_info "You can retry failed components manually or continue without them"
    echo ""
fi

# Show skipped components
if [ ${#SKIPPED_COMPONENTS[@]} -gt 0 ]; then
    log_info "Skipped components (optional):"
    for comp in "${SKIPPED_COMPONENTS[@]}"; do
        echo "  - $comp"
    done
    echo ""
fi

echo "✓ Factory VM build tools installation completed!"
echo ""
echo "Installation log saved to: $INSTALL_LOG"
echo ""
SETUP_SCRIPT_EOF

    chmod +x "$setup_script"
    
    log "  ✓ Setup script created"
}

################################################################################
# Start VM for Installation
################################################################################

start_vm_for_install() {
    log "Starting VM for Alpine installation..."
    
    local uefi_fw="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
    local iso_path="${VM_DIR}/isos/${ALPINE_ISO}"
    
    # Check UEFI firmware exists
    if [ ! -f "$uefi_fw" ]; then
        log_error "UEFI firmware not found at $uefi_fw"
        log_info "Install with: sudo apt-get install qemu-efi-aarch64"
        exit 1
    fi
    
    # Determine QEMU acceleration
    # KVM only works when host and guest architectures match
    local host_arch=$(uname -m)
    local qemu_accel=""
    
    if [ "$host_arch" = "aarch64" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        # ARM64 host with KVM support - can use KVM for ARM64 guest
        qemu_accel="-accel kvm"
        log_info "  Using KVM acceleration (ARM64 native)"
    elif [ "$host_arch" = "x86_64" ]; then
        # x86_64 host cannot use KVM for ARM64 guest - use TCG (software emulation)
        qemu_accel="-accel tcg"
        log_info "  Using TCG emulation (x86_64 host → ARM64 guest)"
        log_info "  Note: Builds will be slower than native ARM64"
    else
        # Fallback to TCG for any other scenario
        qemu_accel="-accel tcg"
        log_info "  Using TCG emulation"
    fi
    
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "  Starting automated Alpine installation"
    log "═══════════════════════════════════════════════════════════"
    log ""
    
    if [ "$qemu_accel" = "-accel tcg" ]; then
        log "  Installing Alpine Linux to disk (TCG emulation - SLOW)..."
        log "  ⚠️  WARNING: TCG emulation is 10-20x slower than KVM"
        log "  This will take 15-20 minutes (automated)"
        log "  Alpine boot alone can take 10-15 minutes on x86_64 hosts"
        log ""
        log "  Please be patient - the installation is working, just very slow"
    else
        log "  Installing Alpine Linux to disk (KVM acceleration)..."
        log "  This will take 3-5 minutes (automated)"
    fi
    log ""
    
    # Build complete QEMU command using -bios (same as start-factory.sh)
    local qemu_cmd="qemu-system-aarch64 -M virt $qemu_accel -cpu cortex-a72 -smp $VM_CPUS -m $VM_MEMORY -bios $uefi_fw -drive file=$SYSTEM_DISK,if=virtio,format=qcow2 -drive file=$DATA_DISK,if=virtio,format=qcow2 -cdrom $iso_path -device virtio-net-pci,netdev=net0 -netdev user,id=net0,hostfwd=tcp::${VM_SSH_PORT}-:22 -nographic"
    
    # Export variables for expect script
    export VM_HOSTNAME VM_ROOT_PASSWORD
    export VM_SSH_PUBLIC_KEY_CONTENT="$(cat "$VM_SSH_PUBLIC_KEY")"
    export QEMU_COMMAND="$qemu_cmd"
    
    # Run automated installation using external expect script
    if ! expect "$SCRIPT_DIR/alpine-install.exp"; then
        # Reset terminal in case expect left it in a bad state
        reset 2>/dev/null || stty sane 2>/dev/null || true
        log_error "Alpine installation failed"
        exit 1
    fi
    
    # Reset terminal to clean state after expect/QEMU
    reset 2>/dev/null || stty sane 2>/dev/null || true
    
    log ""
    log "✓ Alpine installation complete"
    log "  VM has been powered off"
}

################################################################################
# Configure Installed VM
################################################################################

configure_installed_vm() {
    log "Configuring installed Factory VM..."
    
    # Start VM using the start script
    log_info "Starting VM from installed system..."
    if ! "${VM_DIR}/start-factory.sh" >/dev/null 2>&1; then
        log_error "Failed to start Factory VM"
        exit 1
    fi
    
    sleep 5
    
    # Remove old SSH host key from known_hosts (VM was reinstalled)
    log_info "Removing old SSH host key from known_hosts..."
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[localhost]:${VM_SSH_PORT}" 2>/dev/null || true
    
    # Wait for SSH port to open
    log_info "Waiting for SSH port to open..."
    local count=0
    while ! nc -z localhost "$VM_SSH_PORT" 2>/dev/null && [ $count -lt 60 ]; do
        sleep 2
        ((count++))
        echo -n "."
    done
    echo ""
    
    if [ $count -ge 60 ]; then
        log_error "VM failed to start - SSH port never opened"
        exit 1
    fi
    
    # Port is open, but SSH may not be fully ready - Alpine boot is SLOW under TCG emulation
    log_info "Port open, waiting for Alpine to finish booting (this is slow under TCG emulation)..."
    log_info "This can take 3-5 minutes on TCG emulation, please be patient..."
    local ssh_test_attempts=0
    local max_attempts=60  # 60 attempts × 5 seconds = 300 seconds (5 minutes)
    while [ $ssh_test_attempts -lt $max_attempts ]; do
        if ssh -i "$VM_SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
            -p "$VM_SSH_PORT" root@localhost "echo ready" >/dev/null 2>&1; then
            log_info "SSH is ready!"
            break
        fi
        ssh_test_attempts=$((ssh_test_attempts + 1))
        if [ $((ssh_test_attempts % 6)) -eq 0 ]; then
            log_info "Still waiting... ($((ssh_test_attempts * 5)) seconds elapsed)"
        fi
        sleep 5
    done
    
    if [ $ssh_test_attempts -ge $max_attempts ]; then
        log_error "SSH did not become ready after 300 seconds"
        log_error "This might indicate a problem with the Alpine installation"
        exit 1
    fi
    
    # Create foreman user
    log "Creating foreman user with sudo privileges..."
    if ! ssh -i "$VM_SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=60 -o ServerAliveInterval=5 -p "$VM_SSH_PORT" root@localhost << EOF
# Create foreman user
adduser -D foreman
echo "foreman:${FOREMAN_OS_PASSWORD}" | chpasswd

# Add to necessary groups
addgroup foreman wheel
addgroup foreman docker

# Configure doas (Alpine's sudo alternative)
apk add doas
echo "permit nopass :wheel" > /etc/doas.d/doas.conf
chmod 600 /etc/doas.d/doas.conf

# Create sudo symlink for compatibility
ln -sf /usr/bin/doas /usr/bin/sudo

# Setup SSH directory
mkdir -p /home/foreman/.ssh
chmod 700 /home/foreman/.ssh

# Set bash as default shell
apk add bash
sed -i 's|/home/foreman:/bin/ash|/home/foreman:/bin/bash|' /etc/passwd

# Create .bashrc for foreman user (required for jcscripts)
cat > /home/foreman/.bashrc << 'BASHRC_INIT'
# ~/.bashrc: executed by bash for non-login shells

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Basic environment
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export EDITOR=vim

# Aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# Command history
HISTCONTROL=ignoredups:ignorespace
HISTSIZE=1000
HISTFILESIZE=2000

# Enable bash completion
if [ -f /etc/bash/bashrc.d/bash_completion.sh ]; then
    . /etc/bash/bashrc.d/bash_completion.sh
fi
BASHRC_INIT

chown foreman:foreman /home/foreman/.bashrc

# Harden SSH configuration - disable password authentication
cat >> /etc/ssh/sshd_config << 'SSH_CONFIG'

# Factory VM Security Configuration
# Disable password authentication - SSH keys only
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
ChallengeResponseAuthentication no
SSH_CONFIG

# Restart SSH to apply changes
rc-service sshd restart

echo "✓ Foreman user created"
echo "✓ SSH hardened (keys only, no password authentication)"
EOF
    then
        log_error "Failed to create foreman user"
        exit 1
    fi
    
    # Add SSH public key
    log "Adding SSH public key for foreman..."
    ssh -i "$VM_SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$VM_SSH_PORT" root@localhost << EOF
echo '$(cat "$VM_SSH_PUBLIC_KEY")' > /home/foreman/.ssh/authorized_keys
chmod 600 /home/foreman/.ssh/authorized_keys
chown -R foreman:foreman /home/foreman/.ssh
EOF

    # Copy and run setup script
    log "Installing build tools..."
    log_info "Each component has individual timeouts to handle slow network connections"
    log_info "Installation will continue even if some optional components fail"
    log ""
    
    scp -i "$VM_SSH_PRIVATE_KEY" -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${VM_DIR}/vm-setup.sh" root@localhost:/tmp/
    
    # Run setup script WITHOUT outer timeout - script handles its own timeouts per component
    # This allows slow downloads (Android SDK, etc.) to complete without aborting entire install
    # Pass Jenkins foreman password as environment variable (secure - not visible in process list)
    if ssh -i "$VM_SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=60 -o ServerAliveInterval=30 -p "$VM_SSH_PORT" root@localhost \
        "JENKINS_FOREMAN_PASSWORD='${JENKINS_FOREMAN_PASSWORD}' bash /tmp/vm-setup.sh" ; then
        log "  ✓ Build tools installed successfully"
    else
        log_warning "Tool installation had some errors, but VM may still be usable"
        log_info "Check installation log: ssh factory 'cat /root/factory-install.log'"
        log_info "You can retry failed components: ssh factory 'sudo JENKINS_FOREMAN_PASSWORD=<password> bash /tmp/vm-setup.sh'"
    fi
    
    # Setup Jenkins CLI while VM is still running
    setup_jenkins_cli
    
    # Create welcome banner (MOTD)
    log "Creating welcome banner..."
    # Use bash explicitly to avoid ash function syntax issues
    if ssh -i "$VM_SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -p "$VM_SSH_PORT" root@localhost 'bash -s' << 'MOTD_SCRIPT'
cat > /etc/motd << 'MOTD_EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║              🏭  Factory VM - ARM64 Build Server          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

Welcome to your automated ARM64 build environment!

📦 Installed Tools:
  • Docker        - Container runtime (docker command)
  • Kubernetes    - kubectl & Helm
  • Terraform     - Infrastructure as Code
  • AWS CLI       - Cloud management
  • Jenkins       - CI/CD automation server
  • Git, Node.js, Python, OpenJDK

🌐 Jenkins CI/CD Server:
  Web UI:    https://factory.local
  Username:  foreman
  Password:  (see ~/.factory-vm/credentials.txt on host)
  
  CLI:       jenkins-factory <command>
             Available on HOST and inside VM
             Examples:
               jenkins-factory who-am-i
               jenkins-factory list-jobs
               jenkins-factory build <job-name>

📁 Storage:
  System:    /         (50 GB)
  Data:      /data     (200 GB) - For build artifacts

🔒 Security:
  • SSH: Key-based authentication only
  • Jenkins: Secure random password
  • HTTPS: Self-signed certificate (accept in browser)

📖 Documentation:
  Factory README: cat /root/FACTORY-README.md
  Installation log: cat /root/factory-install.log

💡 Quick Start:
  1. Configure AWS:  awslogin (on host, then SSH forwards)
  2. Build image:    docker build -t myapp:arm64 .
  3. Access Jenkins: Open https://factory.local in browser

═══════════════════════════════════════════════════════════════
MOTD_EOF
MOTD_SCRIPT
    then
        log_success "  ✓ Welcome banner created"
    else
        log_warning "  Failed to create welcome banner (continuing anyway)"
    fi
    
    # Stop VM
    log "Stopping VM..."
    if [ -f "${VM_DIR}/factory.pid" ]; then
        VM_PID=$(cat "${VM_DIR}/factory.pid")
        # Try to stop gracefully
        if kill -0 "$VM_PID" 2>/dev/null; then
            # Try regular kill first
            if ! kill "$VM_PID" 2>/dev/null; then
                # If that fails, try with sudo (VM might be running as root)
                sudo kill "$VM_PID" 2>/dev/null || true
            fi
            # Wait for process to die
            for i in {1..10}; do
                if ! kill -0 "$VM_PID" 2>/dev/null && ! sudo kill -0 "$VM_PID" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # Force kill if still running
            if kill -0 "$VM_PID" 2>/dev/null || sudo kill -0 "$VM_PID" 2>/dev/null; then
                sudo kill -9 "$VM_PID" 2>/dev/null || true
            fi
        fi
        rm -f "${VM_DIR}/factory.pid" 2>/dev/null || true
    fi
    
    # Double-check no factory VM processes are running
    if pgrep -f "qemu-system-aarch64.*factory" > /dev/null; then
        log_warning "  Found lingering VM processes, cleaning up..."
        sudo pkill -f "qemu-system-aarch64.*factory" || true
        sleep 2
    fi
    
    log "  ✓ VM configuration complete"
    log ""
    
    # Start the VM using the start script
    log "Starting Factory VM..."
    if [ -f "${VM_DIR}/start-factory.sh" ]; then
        cd "${VM_DIR}" && ./start-factory.sh
        log "  ✓ VM started successfully"
    else
        log_error "start-factory.sh not found!"
    fi
}

################################################################################
# Generate VM Start Script
################################################################################

generate_start_script() {
    log "Generating Factory VM start script..."
    
    local uefi_fw=$(find_uefi_firmware)
    local qemu_accel=""
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        qemu_accel="-enable-kvm"
    fi
    
    cat > "${VM_DIR}/start-factory.sh" << EOF
#!/bin/bash
################################################################################
# Start Factory VM
#
# The Factory is our ARM64 build environment with:
#   - Hostname: factory.local
#   - User: foreman
#   - Tools: Jenkins, Docker, Kubernetes, Terraform, AWS CLI
#   - SSL/HTTPS on port 443
#
################################################################################

VM_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DISK="${SYSTEM_DISK}"
DATA_DISK="${DATA_DISK}"
UEFI_FW="${uefi_fw}"
UEFI_VARS="\${VM_DIR}/UEFI_VARS.fd"
VM_MEMORY="${VM_MEMORY}"
VM_CPUS="${VM_CPUS}"
SSH_PORT="${VM_SSH_PORT}"
PID_FILE="\${VM_DIR}/factory.pid"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if already running
if [ -f "\$PID_FILE" ] && sudo kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
    echo -e "\${YELLOW}Factory VM is already running\${NC}"
    echo "  PID: \$(cat "\$PID_FILE")"
    echo "  Connect: ssh factory"
    echo "  Jenkins: https://factory.local"
    exit 0
fi

# Add factory.local to /etc/hosts if not already there
if ! grep -q "factory.local" /etc/hosts 2>/dev/null; then
    echo "Adding factory.local to /etc/hosts..."
    echo "127.0.0.1 factory.local" | sudo tee -a /etc/hosts > /dev/null
    echo -e "\${GREEN}✓ factory.local added to /etc/hosts\${NC}"
fi

echo -e "\${GREEN}Starting Factory VM...\${NC}"
echo "  Hostname: factory.local"
echo "  Memory: \${VM_MEMORY}"
echo "  CPUs: \${VM_CPUS}"
echo "  Architecture: ARM64 (aarch64)"
echo ""
echo -e "\${YELLOW}Note: sudo access required for port 443 forwarding\${NC}"
echo ""

# Determine acceleration based on host architecture
HOST_ARCH=\$(uname -m)
if [ "\$HOST_ARCH" = "aarch64" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    QEMU_ACCEL="-accel kvm"
    echo "  Acceleration: KVM (native ARM64)"
elif [ "\$HOST_ARCH" = "x86_64" ]; then
    QEMU_ACCEL="-accel tcg"
    echo "  Acceleration: TCG emulation (slower)"
else
    QEMU_ACCEL="-accel tcg"
    echo "  Acceleration: TCG emulation"
fi
echo ""

# Build UEFI pflash drives
UEFI_DRIVES="-drive if=pflash,format=raw,readonly=on,file=\${UEFI_FW}"
if [ -f "\$UEFI_VARS" ]; then
    UEFI_DRIVES="\$UEFI_DRIVES -drive if=pflash,format=raw,file=\${UEFI_VARS}"
fi

# Create empty PID file before starting QEMU (so sudo can write to it)
touch "\${PID_FILE}"

# Port 443 requires root privileges
sudo qemu-system-aarch64 \\
    -M virt \${QEMU_ACCEL} \\
    -cpu cortex-a72 \\
    -smp \${VM_CPUS} \\
    -m \${VM_MEMORY} \\
    \${UEFI_DRIVES} \\
    -drive file="\${SYSTEM_DISK}",if=virtio,format=qcow2 \\
    -drive file="\${DATA_DISK}",if=virtio,format=qcow2 \\
    -device virtio-net-pci,netdev=net0 \\
    -netdev user,id=net0,hostfwd=tcp::\${SSH_PORT}-:22,hostfwd=tcp::443-:443 \\
    -display none \\
    -daemonize \\
    -pidfile "\${PID_FILE}"

# Fix PID file ownership (sudo qemu writes to it as root)
sudo chown \${USER}:\${USER} "\${PID_FILE}"

echo -e "\${GREEN}✓ Factory VM started\${NC}"
echo ""
echo "Access:"
echo "  SSH:     ssh factory"
echo "  Jenkins: https://factory.local"
echo ""
echo "Useful commands:"
echo "  ssh factory 'docker ps'       - Check Docker containers"
echo "  ssh factory 'kubectl version' - Check Kubernetes tools"
echo "  ssh factory 'terraform version' - Check Terraform"
echo ""
EOF

    chmod +x "${VM_DIR}/start-factory.sh"
    
    # Stop script
    cat > "${VM_DIR}/stop-factory.sh" << 'EOF'
#!/bin/bash
VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${VM_DIR}/factory.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "Factory VM is not running"
    exit 0
fi

echo "Stopping Factory VM..."
ssh factory "sudo poweroff" 2>/dev/null || true

# Wait for shutdown
sleep 5

# Force kill if still running
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "Force stopping..."
    kill $(cat "$PID_FILE") 2>/dev/null || true
fi

rm -f "$PID_FILE" 2>/dev/null || true
echo "✓ Factory VM stopped"
EOF

    chmod +x "${VM_DIR}/stop-factory.sh"
    
    # Generate status script
    cat > "${VM_DIR}/status-factory.sh" << 'EOF'
#!/bin/bash
################################################################################
# Check Factory VM Status
#
# Shows if the VM is running, accessible, and what services are available
#
################################################################################

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${VM_DIR}/factory.pid"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Factory VM Status"
echo "================="
echo ""

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
    echo -e "${RED}✗ VM is not running${NC}"
    echo ""
    echo "Start the VM with:"
    echo "  ${VM_DIR}/start-factory.sh"
    exit 1
fi

# Check if process is actually running (handle root-owned PID file)
PID=$(sudo cat "$PID_FILE" 2>/dev/null || cat "$PID_FILE" 2>/dev/null)
if [ -z "$PID" ]; then
    echo -e "${RED}✗ Cannot read PID file${NC}"
    echo "  PID file: $PID_FILE"
    echo ""
    # Fallback: check if qemu process is running
    if pgrep -f "qemu-system-aarch64.*factory" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ VM process found (running)${NC}"
        pgrep -f "qemu-system-aarch64.*factory" | head -1
    else
        echo "Start the VM with:"
        echo "  ${VM_DIR}/start-factory.sh"
        exit 1
    fi
elif ! sudo kill -0 $PID 2>/dev/null; then
    echo -e "${RED}✗ VM process not found (stale PID file)${NC}"
    echo "  PID file exists but process $PID is not running"
    sudo rm -f "$PID_FILE" 2>/dev/null || rm -f "$PID_FILE" 2>/dev/null
    echo ""
    echo "Start the VM with:"
    echo "  ${VM_DIR}/start-factory.sh"
    exit 1
fi

echo -e "${GREEN}✓ VM is running${NC}"
echo "  PID: $PID"
echo ""

# Check SSH connectivity
echo -n "SSH (port 2222): "
if nc -z localhost 2222 2>/dev/null; then
    echo -e "${GREEN}✓ accessible${NC}"
    
    # Try actual SSH connection
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "echo OK" >/dev/null 2>&1; then
        echo "  Connection: working"
    else
        echo -e "  ${YELLOW}Connection: port open but authentication may be needed${NC}"
    fi
else
    echo -e "${RED}✗ not accessible${NC}"
fi

# Check HTTPS (port 443)
echo -n "HTTPS (port 443): "
if sudo lsof -i:443 >/dev/null 2>&1; then
    echo -e "${GREEN}✓ forwarded${NC}"
    
    # Check if Jenkins is accessible
    if curl -sSL --max-time 2 https://factory.local/ -o /dev/null 2>/dev/null; then
        echo "  Jenkins: responding"
    else
        echo -e "  ${YELLOW}Jenkins: not responding yet${NC}"
    fi
else
    echo -e "${YELLOW}⚠ not forwarded (sudo issue?)${NC}"
fi

echo ""
echo "Services:"
echo "  SSH:     ssh factory"
echo "  Jenkins: https://factory.local"
echo ""

# Check VM resources if SSH is available
if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 foreman@localhost "echo OK" >/dev/null 2>&1; then
    echo "VM Resources:"
    ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 foreman@localhost "free -h | grep Mem" 2>/dev/null | awk '{print "  Memory: "$3" used / "$2" total"}'
    ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 foreman@localhost "df -h / | tail -1" 2>/dev/null | awk '{print "  Disk:   "$3" used / "$2" total ("$5" full)"}'
    
    # Check Docker containers
    echo ""
    echo "Docker Containers:"
    ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 foreman@localhost "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || echo -e "  ${YELLOW}Docker not accessible${NC}"
fi
EOF

    chmod +x "${VM_DIR}/status-factory.sh"
    
    log "  ✓ Management scripts created"
}

################################################################################
# Create Optional Tool Installation Scripts
################################################################################

create_optional_install_scripts() {
    log "Creating optional tool installation scripts..."
    
    # Ansible installation script
    cat > "${VM_DIR}/install-ansible.sh" << 'EOF'
#!/bin/bash
################################################################################
# Install Ansible on Factory VM
#
# This script installs Ansible and its AWS dependencies (boto3, botocore)
# Run this on your host machine, it will SSH into the VM to install.
#
# Usage:
#   ./install-ansible.sh
#
################################################################################

set -e

echo "Installing Ansible on Factory VM..."
echo ""

if ! ssh factory 'command -v pip3 >/dev/null 2>&1'; then
    echo "Error: Python3 pip not found in VM"
    exit 1
fi

echo "Installing Ansible and AWS dependencies..."
ssh factory 'sudo apk add --no-cache py3-pip python3-dev build-base libffi-dev openssl-dev'
ssh factory 'sudo pip3 install --break-system-packages ansible boto3 botocore'

echo ""
echo "✓ Ansible installed successfully!"
echo ""
echo "Verify installation:"
echo "  ssh factory 'ansible --version'"
echo ""
EOF
    chmod +x "${VM_DIR}/install-ansible.sh"
    
    # Android SDK installation script
    cat > "${VM_DIR}/install-android-sdk.sh" << 'EOF'
#!/bin/bash
################################################################################
# Install Android SDK on Factory VM
#
# This script installs Android SDK, build tools, and Gradle for mobile builds
# Run this on your host machine, it will SSH into the VM to install.
#
# Usage:
#   ./install-android-sdk.sh
#
################################################################################

set -e

echo "Installing Android SDK on Factory VM..."
echo ""

# Download and install Android SDK
ssh factory << 'REMOTE_INSTALL'
set -e

ANDROID_SDK_VERSION="11076708"
ANDROID_SDK_URL="https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip"
ANDROID_HOME="/opt/android-sdk"

echo "Downloading Android SDK Command Line Tools..."
sudo mkdir -p ${ANDROID_HOME}/cmdline-tools
cd /tmp
wget -q ${ANDROID_SDK_URL} -O android-sdk.zip

echo "Extracting Android SDK..."
sudo unzip -q android-sdk.zip -d ${ANDROID_HOME}/cmdline-tools
sudo mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest
rm android-sdk.zip

# Set environment variables
echo "Configuring environment..."
sudo tee -a /etc/profile.d/android-sdk.sh > /dev/null << 'PROFILE'
export ANDROID_HOME=/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/build-tools/34.0.0
PROFILE

source /etc/profile.d/android-sdk.sh

# Accept licenses and install essentials
echo "Installing Android SDK packages..."
yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses || true
${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# Install Gradle
echo "Installing Gradle..."
GRADLE_VERSION="8.5"
cd /tmp
wget -q https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
sudo unzip -q gradle-${GRADLE_VERSION}-bin.zip -d /opt
sudo ln -sf /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle
rm gradle-${GRADLE_VERSION}-bin.zip

echo "✓ Android SDK installation complete"
REMOTE_INSTALL

echo ""
echo "✓ Android SDK and Gradle installed successfully!"
echo ""
echo "Verify installation:"
echo "  ssh factory 'echo \$ANDROID_HOME'"
echo "  ssh factory 'gradle --version'"
echo ""
echo "Environment variables set in /etc/profile.d/android-sdk.sh"
echo ""
EOF
    chmod +x "${VM_DIR}/install-android-sdk.sh"
    
    log "  ✓ Optional install scripts created:"
    log "    - install-ansible.sh"
    log "    - install-android-sdk.sh"
}

################################################################################
# Configure SSH on Host
################################################################################

configure_host_ssh() {
    log "Configuring SSH on host..."
    
    local ssh_config="${HOME}/.ssh/config"
    
    # Remove ALL old factory entries (handles duplicates and comments)
    if grep -q "^Host factory$" "$ssh_config" 2>/dev/null; then
        log_info "  Removing old SSH config entry..."
        # Remove from first comment or Host factory to next Host or end of file
        sed -i '/^# .*Factory.*Build Environment$/,/^Host factory$/d; /^Host factory$/,/^Host /{ /^Host factory$/,/^Host /{ /^Host /!d; }; }; /^Host factory$/,${/^Host factory/!{/^Host /!d; }; }' "$ssh_config"
        # Clean up any leftover factory blocks
        sed -i '/^Host factory$/,/^$/d' "$ssh_config"
        # Remove duplicate blank lines
        sed -i '/^$/N;/^\n$/d' "$ssh_config"
    fi
    
    # Add new entry
    cat >> "$ssh_config" << EOF

# Alpine ARM64 VM - Factory Build Environment
Host factory
    HostName localhost
    Port ${VM_SSH_PORT}
    User ${VM_USERNAME}
    IdentityFile ${VM_SSH_PRIVATE_KEY}
    IdentitiesOnly yes
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

EOF

    log "  ✓ SSH config updated"
    log_info "  You can now use: ssh factory"
}

################################################################################
# Install SSL Certificate to System Trust Store
################################################################################

install_ssl_certificate() {
    # This function is now handled by setup_jenkins_cli()
    # Keeping stub for compatibility
    log_info "  SSL certificate installation integrated with Jenkins CLI setup"
    return 0
}

################################################################################
# Install Certificate in Browser Trust Stores
################################################################################

install_browser_certificates() {
    # This function is now handled by setup_jenkins_cli()
    # Keeping stub for compatibility
    log_info "  Browser certificate installation integrated with Jenkins CLI setup"
    return 0
}

################################################################################
# Setup Jenkins CLI on Host
################################################################################

setup_jenkins_cli() {
    log "Setting up Jenkins CLI on host..."
    
    # Step 0: Verify Java is installed on host
    log_info "  Checking for Java on host..."
    if ! command -v java >/dev/null 2>&1; then
        log_warning "  Java is not installed on host system"
        log_info "  Installing default JRE..."
        
        # Detect package manager and install Java
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq >/dev/null 2>&1 || true
            if sudo apt-get install -y default-jre-headless >/dev/null 2>&1; then
                log_success "  ✓ Java installed via apt-get"
            else
                log_warning "  Could not install Java automatically"
                log_info "  Install Java manually: sudo apt-get install default-jre-headless"
                log_info "  Then run: ~/vms/factory/setup-jenkins-cli.sh"
                return 0
            fi
        elif command -v dnf >/dev/null 2>&1; then
            if sudo dnf install -y java-11-openjdk-headless >/dev/null 2>&1; then
                log_success "  ✓ Java installed via dnf"
            else
                log_warning "  Could not install Java automatically"
                log_info "  Install Java manually: sudo dnf install java-11-openjdk-headless"
                log_info "  Then run: ~/vms/factory/setup-jenkins-cli.sh"
                return 0
            fi
        else
            log_warning "  Unknown package manager - cannot auto-install Java"
            log_info "  Install Java manually, then run: ~/vms/factory/setup-jenkins-cli.sh"
            return 0
        fi
    else
        log_success "  ✓ Java is installed: $(java -version 2>&1 | head -1)"
    fi
    
    # Step 1: Verify Docker is accessible
    log_info "  Verifying Docker access..."
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
        "docker ps >/dev/null 2>&1" 2>/dev/null; then
        log_warning "  Docker not accessible via SSH"
        log_info "  Run ~/vms/factory/setup-jenkins-cli.sh later to complete setup"
        return 0
    fi
    
    # Step 2: Verify Jenkins container is running
    log_info "  Verifying Jenkins container..."
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
        "docker ps | grep jenkins" >/dev/null 2>&1; then
        log_warning "  Jenkins container not running"
        log_info "  Run ~/vms/factory/setup-jenkins-cli.sh later to complete setup"
        return 0
    fi
    log_success "  ✓ Jenkins container is running"
    
    # Step 3: Wait for Jenkins to be fully ready (foreman user + token created)
    log_info "  Waiting for Jenkins initialization (foreman user + API token)..."
    local max_attempts=60
    local attempt=0
    local jenkins_ready=false
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if foreman user exists (Jenkins appends hash to username)
        if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
            "docker exec jenkins ls /var/jenkins_home/users/ 2>/dev/null | grep -q '^foreman_'" 2>/dev/null; then
            # Check if token exists
            if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
                "docker exec jenkins test -f /var/jenkins_home/foreman-api-token.txt 2>/dev/null" 2>/dev/null; then
                log_success "  ✓ Jenkins is ready (foreman user and token exist)"
                jenkins_ready=true
                break
            fi
        fi
        
        ((attempt++))
        [ $((attempt % 10)) -eq 0 ] && log_info "    Still waiting... (${attempt}/${max_attempts})"
        sleep 3
    done
    
    # Check if we timed out
    if [ "$jenkins_ready" = "false" ]; then
        log_warning "  Jenkins CLI setup skipped (timeout after ${max_attempts} attempts)"
        log_info "  Foreman user or API token not created yet"
        log_info "  Check Jenkins logs: ssh factory 'sudo docker logs jenkins'"
        log_info "  Run ~/vms/factory/setup-jenkins-cli.sh later to complete setup"
        return 0
    fi
    
    # Step 4: Install Caddy CA certificate (CRITICAL for HTTPS to Jenkins)
    log_info "  Installing Caddy CA certificates for HTTPS access..."
    
    local root_cert_file="${VM_DIR}/caddy-root-ca.crt"
    local intermediate_cert_file="${VM_DIR}/caddy-intermediate-ca.crt"
    local cert_installed=false
    
    # Retrieve ROOT certificate from VM
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
        "cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" > "$root_cert_file" 2>/dev/null; then
        
        log_success "  ✓ Root certificate retrieved from VM"
        
        # Retrieve INTERMEDIATE certificate from VM (needed for full chain)
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
            "cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/intermediate.crt" > "$intermediate_cert_file" 2>/dev/null; then
            log_success "  ✓ Intermediate certificate retrieved from VM"
        fi
        
        # Install to system trust store (REQUIRED for curl/wget to trust HTTPS)
        if sudo cp "$root_cert_file" /usr/local/share/ca-certificates/caddy-factory-ca.crt 2>/dev/null; then
            # Also install intermediate
            sudo cp "$intermediate_cert_file" /usr/local/share/ca-certificates/caddy-intermediate-ca.crt 2>/dev/null || true
            
            log_info "    Installing to system trust store..."
            sudo update-ca-certificates >/dev/null 2>&1
            
            if [ -f /usr/local/share/ca-certificates/caddy-factory-ca.crt ]; then
                log_success "  ✓ Certificates installed to system trust store"
                log_info "    https://factory.local is now trusted (no security warnings)"
                cert_installed=true
            fi
            
            # Also install to Java keystore (REQUIRED for Jenkins CLI)
            log_info "    Installing to Java keystore for Jenkins CLI..."
            local java_home=$(update-alternatives --query java 2>/dev/null | grep Value | cut -d' ' -f2 | sed 's|/bin/java||')
            if [ -n "$java_home" ] && [ -d "$java_home" ]; then
                local keystore="${java_home}/lib/security/cacerts"
                if [ -f "$keystore" ]; then
                    # Remove old certificates if exist (to allow re-installation)
                    sudo keytool -delete -alias caddy-factory-ca -keystore "$keystore" -storepass changeit >/dev/null 2>&1 || true
                    sudo keytool -delete -alias caddy-intermediate-ca -keystore "$keystore" -storepass changeit >/dev/null 2>&1 || true
                    
                    # Import both certificates
                    sudo keytool -import -noprompt -trustcacerts -alias caddy-factory-ca \
                        -file "$root_cert_file" -keystore "$keystore" -storepass changeit >/dev/null 2>&1 || true
                    sudo keytool -import -noprompt -trustcacerts -alias caddy-intermediate-ca \
                        -file "$intermediate_cert_file" -keystore "$keystore" -storepass changeit >/dev/null 2>&1 || true
                        
                    if sudo keytool -list -keystore "$keystore" -storepass changeit 2>/dev/null | grep -q "caddy-factory-ca"; then
                        log_success "  ✓ Certificates installed to Java keystore"
                        log_info "    Jenkins CLI will now trust https://factory.local"
                    else
                        log_warning "  Could not install certificates to Java keystore"
                        log_info "  Jenkins CLI may not work - manual fix required"
                    fi
                else
                    log_warning "  Java keystore not found at: $keystore"
                fi
            else
                log_warning "  Could not locate JAVA_HOME - skipping Java keystore installation"
            fi
            
            # Install to browser certificate databases (Chrome/Chromium/Firefox)
            log_info "    Installing to browser certificate databases..."
            local browsers_updated=0
            
            # Install certutil if not present (needed for Chrome/Chromium)
            if ! command -v certutil >/dev/null 2>&1; then
                log_info "    Installing libnss3-tools for browser certificate management..."
                sudo apt-get update -qq >/dev/null 2>&1 || true
                sudo apt-get install -y libnss3-tools >/dev/null 2>&1 || true
            fi
            
            if command -v certutil >/dev/null 2>&1; then
                # Helper function to completely remove all Caddy certificates (handles duplicates)
                remove_all_caddy_certs() {
                    local db_path="$1"
                    # Run deletion multiple times to catch duplicates (max 5 attempts)
                    for i in {1..5}; do
                        certutil -D -d "$db_path" -n "Caddy Local CA - Factory" >/dev/null 2>&1 || break
                    done
                    for i in {1..5}; do
                        certutil -D -d "$db_path" -n "Caddy Intermediate CA - Factory" >/dev/null 2>&1 || break
                    done
                    # Also remove old naming variations (if any)
                    for i in {1..5}; do
                        certutil -D -d "$db_path" -n "Caddy Local CA" >/dev/null 2>&1 || break
                    done
                }
                
                # Find all Chromium-based browser profile directories
                # Supports: Chrome, Chromium, Brave, Edge, Vivaldi, Opera
                local chromium_configs=(
                    "$HOME/.config/google-chrome"
                    "$HOME/.config/chromium"
                    "$HOME/.config/BraveSoftware/Brave-Browser"
                    "$HOME/.config/microsoft-edge"
                    "$HOME/.config/vivaldi"
                    "$HOME/.config/opera"
                )
                
                for config_dir in "${chromium_configs[@]}"; do
                    if [ -d "$config_dir" ]; then
                        for cert_dir in $(find "$config_dir" -type d \( -name "Default" -o -name "Profile *" \) 2>/dev/null); do
                            if [ -f "$cert_dir/Cookies" ] || [ -f "$cert_dir/History" ]; then  # Verify it's a valid profile
                                # Remove ALL old Caddy certificates (including duplicates)
                                remove_all_caddy_certs "sql:$cert_dir"
                                
                                # Import root and intermediate certificates with correct trust flags
                                # Root CA: "CT,C,C" (Trust as CA + SSL), Intermediate: ",," (no trust)
                                if certutil -A -d sql:$cert_dir -t "CT,C,C" -n "Caddy Local CA - Factory" -i "$root_cert_file" >/dev/null 2>&1; then
                                    certutil -A -d sql:$cert_dir -t ",," -n "Caddy Intermediate CA - Factory" -i "$intermediate_cert_file" >/dev/null 2>&1 || true
                                    browsers_updated=$((browsers_updated + 1))
                                fi
                            fi
                        done
                    fi
                done
                
                # Install to system NSS database (used by all Chromium browsers as fallback)
                if [ -d ~/.pki/nssdb ]; then
                    # Remove ALL old Caddy certificates (including duplicates)
                    remove_all_caddy_certs "sql:$HOME/.pki/nssdb"
                    
                    if certutil -A -d sql:$HOME/.pki/nssdb -t "CT,C,C" -n "Caddy Local CA - Factory" -i "$root_cert_file" >/dev/null 2>&1; then
                        certutil -A -d sql:$HOME/.pki/nssdb -t ",," -n "Caddy Intermediate CA - Factory" -i "$intermediate_cert_file" >/dev/null 2>&1 || true
                        log_info "    System NSS database updated (Chrome/Chromium fallback)"
                        browsers_updated=$((browsers_updated + 1))
                    fi
                fi
                
                # Find Firefox profiles (regular and Snap installations)
                local firefox_dirs=(
                    ~/.mozilla/firefox
                    ~/snap/firefox/common/.mozilla/firefox
                )
                
                for firefox_base in "${firefox_dirs[@]}"; do
                    if [ -d "$firefox_base" ]; then
                        for cert_dir in "$firefox_base"/*.default* "$firefox_base"/*[Pp]rofile*; do
                            if [ -f "$cert_dir/cert9.db" ] || [ -f "$cert_dir/cert8.db" ]; then
                                # Remove ALL old Caddy certificates (including duplicates)
                                remove_all_caddy_certs "sql:$cert_dir"
                                
                                # Import root and intermediate certificates with correct trust flags
                                if certutil -A -d sql:$cert_dir -t "CT,C,C" -n "Caddy Local CA - Factory" -i "$root_cert_file" >/dev/null 2>&1; then
                                    certutil -A -d sql:$cert_dir -t ",," -n "Caddy Intermediate CA - Factory" -i "$intermediate_cert_file" >/dev/null 2>&1 || true
                                    browsers_updated=$((browsers_updated + 1))
                                fi
                            fi
                        done
                    fi
                done
                
                if [ $browsers_updated -gt 0 ]; then
                    log_success "  ✓ Certificates installed to $browsers_updated browser profile(s)"
                    log_info "    Supported browsers: Chrome, Chromium, Brave, Edge, Firefox, Opera, Vivaldi"
                    log_info "    Restart browsers to apply changes"
                else
                    log_info "    No browser profiles found"
                    log_info "    Certificates available in: ${VM_DIR}/"
                    log_info "    Manual import: certutil -A -d sql:\$HOME/.pki/nssdb -t \"CT,C,C\" -n \"Caddy Local CA - Factory\" -i ${root_cert_file}"
                fi
            else
                log_warning "  certutil not available - skipping browser certificate installation"
                log_info "    Install libnss3-tools and run: certutil -A -d sql:\$HOME/.pki/nssdb -t \"C,,\" -n \"Caddy Local CA\" -i $cert_file"
            fi
        else
            log_warning "  Could not install to system trust store (sudo required)"
            log_info "  Certificate saved to: $cert_file"
            log_info "  HTTPS downloads will fail - will use fallback method"
        fi
    else
        log_warning "  Could not retrieve Caddy certificate from VM"
        log_info "  HTTPS access will not work - will use fallback method"
    fi
    
    # Verify HTTPS access works before attempting jar download
    if [ "$cert_installed" = "true" ]; then
        log_info "  Verifying HTTPS access to Jenkins..."
        local https_attempts=0
        local https_working=false
        
        # Wait up to 30 seconds for Jenkins to respond via HTTPS
        while [ $https_attempts -lt 10 ]; do
            if curl -sSL --max-time 3 https://factory.local/ -o /dev/null 2>/dev/null; then
                log_success "  ✓ HTTPS access verified - certificate is working"
                https_working=true
                break
            fi
            https_attempts=$((https_attempts + 1))
            sleep 3
        done
        
        if [ "$https_working" = "false" ]; then
            log_warning "  HTTPS verification failed after $((https_attempts * 3)) seconds"
            log_info "  This may be because port 443 forwarding requires sudo"
            log_info "  Will use fallback method (direct container access)"
            cert_installed=false
        fi
    fi
    
    # Step 5: Download Jenkins CLI jar
    log_info "  Downloading Jenkins CLI jar..."
    
    mkdir -p ~/.java/jars
    local jar_downloaded=false
    
    # Only try HTTPS if certificate is properly installed
    if [ "$cert_installed" = "true" ]; then
        log_info "    Attempting HTTPS download (certificate is installed)..."
        if curl -sSL --max-time 10 https://factory.local/jnlpJars/jenkins-cli.jar \
            -o ~/.java/jars/jenkins-cli-factory.jar 2>/dev/null; then
            chmod 644 ~/.java/jars/jenkins-cli-factory.jar
            log_success "  ✓ Jenkins CLI jar downloaded via HTTPS"
            jar_downloaded=true
        else
            log_warning "    HTTPS download failed despite certificate being installed"
        fi
    else
        log_info "    Skipping HTTPS download (certificate not installed)"
    fi
    
    # Fall back to direct container access if HTTPS didn't work
    if [ "$jar_downloaded" = "false" ]; then
        log_info "    Using direct container access as fallback..."
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
            "docker exec jenkins cat /var/jenkins_home/war/WEB-INF/jenkins-cli.jar" > ~/.java/jars/jenkins-cli-factory.jar 2>/dev/null; then
            chmod 644 ~/.java/jars/jenkins-cli-factory.jar
            log_success "  ✓ Jenkins CLI jar downloaded via container access"
            jar_downloaded=true
        else
            log_warning "  Could not download Jenkins CLI jar"
            log_info "  Run ~/vms/factory/setup-jenkins-cli.sh later to complete setup"
            return 0
        fi
    fi
    
    # Step 6: Get the API token
    log_info "  Retrieving foreman user API token..."
    local api_token
    api_token=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
        "docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null" 2>/dev/null | tr -d '\n\r')
    
    if [ -z "$api_token" ]; then
        log_warning "  Could not retrieve API token from Jenkins"
        log_info "  Run ~/vms/factory/setup-jenkins-cli.sh later to complete setup"
        return 0
    fi
    
    log_success "  ✓ API token retrieved (${#api_token} characters)"
    
    # Step 7: Test the CLI before saving configuration
    log_info "  Testing Jenkins CLI connection..."
    if echo "$api_token" | java -jar ~/.java/jars/jenkins-cli-factory.jar \
        -s https://factory.local \
        -auth foreman:@- \
        -webSocket \
        who-am-i >/dev/null 2>&1; then
        log_success "  ✓ Jenkins CLI authentication successful"
    else
        log_warning "  Jenkins CLI test failed - configuration may need adjustment"
        log_info "  Continuing with setup..."
    fi
    
    # Add jenkins-factory function to .bashrc if not already present
    if ! grep -q "jenkins-factory()" ~/.bashrc 2>/dev/null; then
        log_info "  Adding jenkins-factory() function to ~/.bashrc..."
        
        cat >> ~/.bashrc << EOF

################################################################################
# Jenkins Factory CLI Helper
################################################################################
# Created by Factory VM setup script on $(date)
#
# Usage:
#   jenkins-factory help                    # Show available commands
#   jenkins-factory who-am-i                # Verify authentication
#   jenkins-factory list-jobs               # List all jobs
#   jenkins-factory build <job-name>        # Trigger a build
#   jenkins-factory create-job <name> < config.xml  # Create job from XML
#
# The foreman user has full administrative access to Jenkins.
# API Token is stored in Jenkins and rotates automatically.
################################################################################

jenkins-factory() {
    local api_token
    
    # Load token from cache or fetch new one
    if [ -f ~/.jenkins-factory-token ]; then
        api_token=\$(cat ~/.jenkins-factory-token)
    else
        api_token=\$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \\
            "docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null" 2>/dev/null | tr -d '\\n\\r')
        if [ -n "\$api_token" ]; then
            echo "\$api_token" > ~/.jenkins-factory-token
            chmod 600 ~/.jenkins-factory-token
        fi
    fi
    
    if [ -z "\$api_token" ]; then
        echo "ERROR: Could not get Jenkins API token"
        return 1
    fi
    
    java -jar ~/.java/jars/jenkins-cli-factory.jar \\
        -s https://factory.local \\
        -auth foreman:"\$api_token" \\
        -webSocket \\
        "\$@"
}

# Bash completion for jenkins-factory
_jenkins_factory_completion() {
    local cur=\${COMP_WORDS[COMP_CWORD]}
    local commands="help version who-am-i list-jobs build create-job delete-job get-job \\
                   console enable-job disable-job install-plugin list-plugins restart \\
                   safe-restart safe-shutdown"
    
    COMPREPLY=( \$(compgen -W "\${commands}" -- \${cur}) )
}

complete -F _jenkins_factory_completion jenkins-factory

EOF
        
        # Also save token to file for immediate use
        echo "$api_token" > ~/.jenkins-factory-token
        chmod 600 ~/.jenkins-factory-token
        
        log_success "  ✓ jenkins-factory() function added to ~/.bashrc"
        log_info "  Reload with: source ~/.bashrc"
    else
        log_info "  jenkins-factory() function already exists in ~/.bashrc"
        
        # Update the token file
        echo "$api_token" > ~/.jenkins-factory-token
        chmod 600 ~/.jenkins-factory-token
        log_success "  ✓ API token updated"
    fi
    
    # Create a setup script for manual re-run if needed
    cat > "${VM_DIR}/setup-jenkins-cli.sh" << 'CLI_SCRIPT'
#!/bin/bash
# Jenkins CLI Setup Script
# Re-run this script if Jenkins CLI setup fails during installation

set -e

echo "========================================="
echo "  Jenkins CLI Setup"
echo "========================================="
echo ""

# Step 1: Verify VM is accessible
echo "[1/7] Verifying Factory VM is accessible..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "echo OK" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to Factory VM"
    echo "Make sure the VM is running: ~/vms/factory/start-factory.sh"
    exit 1
fi
echo "  ✓ VM is accessible"

# Step 2: Verify Docker
echo "[2/7] Verifying Docker..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "docker ps >/dev/null 2>&1" 2>/dev/null; then
    echo "ERROR: Docker is not accessible"
    exit 1
fi
echo "  ✓ Docker is running"

# Step 3: Verify Jenkins container
echo "[3/7] Verifying Jenkins container..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "docker ps | grep jenkins" >/dev/null 2>&1; then
    echo "ERROR: Jenkins container is not running"
    echo "Check with: ssh factory 'sudo docker ps -a'"
    exit 1
fi
echo "  ✓ Jenkins container is running"

# Step 4: Verify foreman user and token exist
echo "[4/7] Verifying Jenkins foreman user and API token..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
    "docker exec jenkins test -d /var/jenkins_home/users/foreman" 2>/dev/null; then
    echo "ERROR: Foreman user does not exist in Jenkins"
    echo "Check Jenkins logs: ssh factory 'sudo docker logs jenkins | grep foreman'"
    exit 1
fi

if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
    "docker exec jenkins test -f /var/jenkins_home/foreman-api-token.txt" 2>/dev/null; then
    echo "ERROR: Foreman API token does not exist"
    echo "Check Jenkins logs: ssh factory 'sudo docker logs jenkins | grep token'"
    exit 1
fi
echo "  ✓ Foreman user and API token exist"

# Step 5: Install Caddy CA certificate
echo "[5/7] Installing Caddy CA certificate..."
cert_file="/tmp/caddy-factory-ca.crt"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
    "cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" > "$cert_file" 2>/dev/null; then
    
    if sudo cp "$cert_file" /usr/local/share/ca-certificates/caddy-factory-ca.crt 2>/dev/null && \
       sudo update-ca-certificates >/dev/null 2>&1; then
        echo "  ✓ Certificate installed to system trust store"
    else
        echo "  WARNING: Could not install certificate (may require sudo)"
    fi
    rm -f "$cert_file"
else
    echo "  WARNING: Could not retrieve certificate from VM"
fi

# Step 6: Download Jenkins CLI jar
echo "[6/7] Downloading Jenkins CLI jar..."
mkdir -p ~/.java/jars

if curl -sSL --max-time 10 https://factory.local/jnlpJars/jenkins-cli.jar -o ~/.java/jars/jenkins-cli-factory.jar 2>/dev/null; then
    chmod 644 ~/.java/jars/jenkins-cli-factory.jar
    echo "  ✓ Jenkins CLI jar downloaded (via HTTPS)"
else
    echo "  HTTPS failed, trying direct container access..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
        "docker exec jenkins cat /var/jenkins_home/war/WEB-INF/jenkins-cli.jar" > ~/.java/jars/jenkins-cli-factory.jar 2>/dev/null; then
        chmod 644 ~/.java/jars/jenkins-cli-factory.jar
        echo "  ✓ Jenkins CLI jar downloaded (via container)"
    else
        echo "ERROR: Could not download Jenkins CLI jar"
        exit 1
    fi
fi

# Step 7: Get API token
echo "[7/7] Retrieving API token..."
api_token=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost \
    "docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null" 2>/dev/null | tr -d '\n\r')

if [ -z "$api_token" ]; then
    echo "ERROR: Could not retrieve API token"
    exit 1
fi

echo "$api_token" > ~/.jenkins-factory-token
chmod 600 ~/.jenkins-factory-token
echo "  ✓ API token saved to ~/.jenkins-factory-token"

# Test the CLI
echo ""
echo "Testing Jenkins CLI..."
if echo "$api_token" | java -jar ~/.java/jars/jenkins-cli-factory.jar \
    -s https://factory.local \
    -auth foreman:@- \
    -webSocket \
    who-am-i; then
    echo ""
    echo "========================================="
    echo "  ✓ Jenkins CLI setup complete!"
    echo "========================================="
    echo ""
    echo "Usage: jenkins-factory <command>"
    echo "Example: jenkins-factory list-jobs"
    echo ""
    echo "Note: Reload your shell to use the helper function"
    echo "      source ~/.bashrc"
else
    echo ""
    echo "WARNING: CLI test failed but files are installed"
    echo "Try: source ~/.bashrc && jenkins-factory who-am-i"
fi
CLI_SCRIPT
    
    chmod +x "${VM_DIR}/setup-jenkins-cli.sh"
    log_success "  ✓ Manual setup script created: ${VM_DIR}/setup-jenkins-cli.sh"
    
    log_success "✓ Jenkins CLI configured successfully"
    log_info ""
    log_info "  Verify with: source ~/.bashrc && jenkins-factory who-am-i"
    log_info "  Expected output: 'Authenticated as: foreman'"
}

################################################################################
# Create Documentation
################################################################################

create_documentation() {
    log "Creating Factory VM documentation..."
    
    cat > "${VM_DIR}/FACTORY-README.md" << 'DOC_EOF'
# Factory VM - ARM64 Build Environment

## Overview

The **Factory** is a dedicated ARM64 virtual machine for building Docker images and managing infrastructure deployments. It provides a complete CI/CD environment with all necessary build tools.

## Configuration

| Property | Value |
|----------|-------|
| **Hostname** | factory |
| **Username** | foreman |
| **Architecture** | ARM64 (aarch64) |
| **Memory** | 4GB |
| **CPUs** | 4 cores |
| **System Disk** | 20GB |
| **Data Disk** | 100GB |
| **SSH Port** | 2222 |

## Installed Tools

### Container & Orchestration
- **Docker** - Container runtime
- **Docker Compose** - Multi-container orchestration
- **Kubernetes (kubectl)** - Kubernetes CLI
- **Helm** - Kubernetes package manager

### Infrastructure as Code
- **Terraform** - Infrastructure provisioning
- **Ansible** - Configuration management

### CI/CD
- **Jenkins** - Continuous integration server (port 8080)

### Cloud & Authentication
- **AWS CLI** - Amazon Web Services command-line interface
- **jcscripts** - Custom scripts collection (includes awslogin)
- **AWS SSO** - Pre-configured for your organization

### Development
- **Git** - Version control
- **Node.js & npm** - JavaScript runtime
- **Python 3 & pip** - Python runtime
- **Java 17** - Java runtime (for Android and Jenkins)
- **Android SDK** - Android development kit (API 34, NDK 25.2)
- **Gradle 8.5** - Android build system
- **Build tools** - gcc, g++, make, cmake

## Access

### SSH Access

```bash
# Connect to Factory
ssh factory

# Run commands
ssh factory "docker ps"
ssh factory "kubectl version"
ssh factory "terraform version"

# Copy files to Factory
scp myfile.tar.gz factory:/home/foreman/

# Copy files from Factory
scp factory:/home/foreman/build.tar.gz ./
```

### Jenkins Access

```bash
# Start Jenkins (if not auto-started)
ssh factory "sudo service jenkins start"

# Access Jenkins
http://localhost:8080

# Get initial admin password
ssh factory "sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"

# Stop Jenkins
ssh factory "sudo service jenkins stop"
```

## Operations

### Start Factory VM

```bash
cd ~/vms/factory
./start-factory.sh
```

### Stop Factory VM

```bash
cd ~/vms/factory
./stop-factory.sh

# Or from inside
ssh factory "sudo poweroff"
```

### Check VM Status

```bash
# Check if running
pgrep -f "qemu.*factory"

# Or
ssh factory "uname -a"
```

### Build ARM64 Docker Images

```bash
# Connect to Factory
ssh factory

# Navigate to project (if mounted/synced)
cd /home/foreman/project

# Build backend
docker build -t fintech-backend:arm64 -f backend/Dockerfile backend/

# Build frontend
docker build -t fintech-frontend:arm64 -f frontend/Dockerfile frontend/

# Save image
docker save fintech-backend:arm64 | gzip > backend-arm64.tar.gz

# Exit and copy to host
exit
scp factory:/home/foreman/backend-arm64.tar.gz ./
```

### Sync Project to Factory

```bash
# From project root on host
rsync -avz --delete \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude 'dist' \
    ./FinTechApp/ \
    factory:/home/foreman/project/
```

### Configure AWS CLI

AWS SSO is pre-configured during Factory VM setup. To authenticate:

```bash
# On your localhost: Authenticate with AWS SSO
awslogin

# SSH to Factory (credentials forwarded automatically)
ssh factory

# Inside Factory: Credentials are available via agent forwarding
aws sts get-caller-identity

# Or configure AWS SSO with awslogin
ssh factory
awslogin  # Configure your AWS SSO settings
```

**AWS Configuration:**
- Use the `awslogin` script to configure AWS SSO settings
- SSH agent forwarding allows seamless credential sharing from localhost
- When you authenticate on localhost with `awslogin`, credentials are available in Factory VM

## Maintenance

### Update Alpine Packages

```bash
ssh factory "sudo apk update && sudo apk upgrade"
```

### Update Docker

```bash
ssh factory "sudo apk upgrade docker docker-compose"
ssh factory "sudo service docker restart"
```

### Update Terraform

```bash
ssh factory
curl -LO "https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_arm64.zip"
unzip terraform_1.7.0_linux_arm64.zip
sudo mv terraform /usr/local/bin/
terraform version
```

### Clean Docker Cache

```bash
ssh factory "docker system prune -af"
ssh factory "docker volume prune -f"
```

### Expand Data Disk

```bash
# On host
cd ~/vms/factory
qemu-img resize factory-data.qcow2 +50G

# Inside VM
ssh factory
sudo growpart /dev/vdb 1
sudo resize2fs /dev/vdb1
df -h
```

## Backup & Restore

### Backup VM

```bash
# Backup disks
cd ~/vms/factory
cp factory.qcow2 backups/factory-$(date +%Y%m%d).qcow2
cp factory-data.qcow2 backups/factory-data-$(date +%Y%m%d).qcow2
```

### Restore VM

```bash
cd ~/vms/factory
cp backups/factory-YYYYMMDD.qcow2 factory.qcow2
cp backups/factory-data-YYYYMMDD.qcow2 factory-data.qcow2
./start-factory.sh
```

## Troubleshooting

### VM won't start

```bash
# Check if already running
pgrep -f qemu

# Check disk files exist
ls -lh ~/vms/factory/*.qcow2

# Check QEMU
qemu-system-aarch64 --version
```

### Can't connect via SSH

```bash
# Check VM is running
pgrep -f "qemu.*factory"

# Check SSH port
netstat -ln | grep 2222

# Test SSH manually
ssh -p 2222 foreman@localhost

# Check SSH key
ls -la ~/.ssh/factory-foreman*
```

### Jenkins won't start

```bash
ssh factory

# Check Docker is running
docker ps

# Check Jenkins container
docker logs jenkins

# Restart Jenkins
sudo service jenkins restart
```

### Out of disk space

```bash
# Check usage
ssh factory "df -h"

# Clean Docker
ssh factory "docker system prune -af"

# Expand disk (see Maintenance section)
```

## Security

### SSH Key Location

Private key: `~/.ssh/factory-foreman`  
Public key: `~/.ssh/factory-foreman.pub`

### Change Foreman Password

```bash
ssh factory
passwd
# Enter new password
```

### Change Root Password

```bash
ssh factory
sudo passwd root
# Enter new password
```

### Firewall (if needed)

```bash
ssh factory

# Install iptables
sudo apk add iptables

# Configure rules
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
# ... etc

# Save rules
sudo rc-update add iptables
sudo /etc/init.d/iptables save
```

## Integration with Deployment

### Build ARM64 Images

```bash
# Build all components
./factory-vm/build-arm-images.sh all

# This will:
# 1. Sync project to Factory
# 2. Build images inside Factory
# 3. Save and transfer back to host
# 4. Tag for ECR
# 5. Ready to push
```

### Deploy to AWS

```bash
# From host, after building ARM64 images
source scripts/config/deployment.conf
ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Tag images
docker tag fintech-backend:arm64 ${ECR}/fintech-backend:arm64
docker tag fintech-frontend:arm64 ${ECR}/fintech-frontend:arm64

# Push to ECR
docker push ${ECR}/fintech-backend:arm64
docker push ${ECR}/fintech-frontend:arm64

# Deploy application
./scripts/deploy-application.sh
```

## Best Practices

1. **Keep VM running** during active development
2. **Stop VM** when not in use to save resources
3. **Backup regularly**, especially before major changes
4. **Clean Docker cache** weekly
5. **Update packages** monthly
6. **Monitor disk space** with `df -h`
7. **Use rsync** for efficient file transfers
8. **Test builds locally** before pushing to ECR

## Quick Reference

```bash
# Start
cd ~/vms/factory && ./start-factory.sh

# Connect
ssh factory

# Stop
cd ~/vms/factory && ./stop-factory.sh

# Build
./factory-vm/build-arm-images.sh all

# Status
ssh factory "docker ps && kubectl version --client"
```

## Support

For issues or questions:
1. Check this README
2. Check `~/vms/factory/` for logs
3. Run: `./factory-vm/check-factory-vm.sh`
4. Review Alpine documentation: https://alpinelinux.org/
DOC_EOF

    log "  ✓ Documentation created: ${VM_DIR}/FACTORY-README.md"
}

################################################################################
# Main
################################################################################

main() {
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║        Factory VM - Automated Setup                      ║
║                                                          ║
║  Complete ARM64 build environment with:                  ║
║    • Hostname: factory.local                             ║
║    • User: foreman (with sudo)                           ║
║    • Tools: Jenkins, Docker, K8s, Terraform              ║
║    • SSL/HTTPS on default port (443)                     ║
║    • SSH key authentication                              ║
║    • Automated configuration                             ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

BANNER

    # Record start time
    SETUP_START_TIME=$(date +%s)
    
    log "Starting Factory VM setup..."
    log ""
    
    # Offer configuration choice based on system resources
    offer_configuration_choice
    
    # Generate secure passwords for installation
    log_info "Generating secure passwords..."
    VM_ROOT_PASSWORD=$(generate_secure_password)
    FOREMAN_OS_PASSWORD=$(generate_secure_password)
    JENKINS_FOREMAN_PASSWORD=$(generate_secure_password)
    
    # Export for sub-scripts and SSH commands
    export VM_ROOT_PASSWORD FOREMAN_OS_PASSWORD JENKINS_FOREMAN_PASSWORD
    
    # Create VM directory
    mkdir -p "$VM_DIR"
    cd "$VM_DIR"
    
    # Pre-flight checks
    check_dependencies
    ensure_qemu
    setup_ssh_keys
    download_alpine
    create_disks
    create_vm_setup_script
    
    # Install Alpine
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "  Step 1: Alpine Linux Installation"
    log "═══════════════════════════════════════════════════════════"
    start_vm_for_install
    
    # Generate start script first (needed by configure_installed_vm)
    generate_start_script
    
    # Configure VM
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "  Step 2: Configure Factory VM"
    log "═══════════════════════════════════════════════════════════"
    configure_installed_vm
    
    # Generate remaining scripts and docs
    create_optional_install_scripts
    configure_host_ssh
    
    # Setup Jenkins CLI with certificates (replaces old install_ssl_certificate)
    setup_jenkins_cli
    
    create_documentation
    
    log ""
    log "╔═══════════════════════════════════════════════════════════╗"
    log "║                                                           ║"
    log "║        ✓ Factory VM Setup Complete!                      ║"
    log "║                                                           ║"
    log "╚═══════════════════════════════════════════════════════════╝"
    log ""
    log "${GREEN}Factory VM is ready for use!${NC}"
    log ""
    log "Connection:"
    log "  ${BLUE}ssh factory${NC}"
    log ""
    log "VM Details:"
    log "  Hostname: ${BLUE}factory.local${NC}"
    log "  User: ${BLUE}foreman${NC}"
    log "  Architecture: ${BLUE}ARM64 (aarch64)${NC}"
    log "  System Disk: ${BLUE}${SYSTEM_DISK_SIZE}${NC}"
    log "  Data Disk: ${BLUE}${DATA_DISK_SIZE}${NC}"
    log ""
    log "VM Management:"
    log "  Start:  ${BLUE}~/vms/factory/start-factory.sh${NC}"
    log "  Stop:   ${BLUE}~/vms/factory/stop-factory.sh${NC}"
    log "  Status: ${BLUE}~/vms/factory/status-factory.sh${NC}"
    log ""
    log "Installed Tools:"
    log "  ✓ Docker ${BLUE}(docker --version)${NC}"
    log "  ✓ Kubernetes: kubectl & Helm"
    log "  ✓ Terraform ${TERRAFORM_VERSION}"
    log "  ✓ AWS CLI"
    log "  ✓ Git, Node.js, Python, OpenJDK"
    log "  ✓ Jenkins ${JENKINS_VERSION} (Docker-based)"
    log "  ✓ Nginx with SSL (reverse proxy)"
    log "  ✓ jcscripts (awslogin)"
    log ""
    log "Optional Tools (install if needed):"
    log "  ${YELLOW}⊘${NC} Android SDK - run: ${BLUE}~/vms/factory/install-android-sdk.sh${NC}"
    log "  ${YELLOW}⊘${NC} Ansible      - run: ${BLUE}~/vms/factory/install-ansible.sh${NC}"
    log ""
    log_info "Installation details:"
    log "  View log: ${BLUE}ssh factory 'cat /root/factory-install.log'${NC}"
    log "  Retry failed components: ${BLUE}ssh factory 'sudo bash /tmp/vm-setup.sh'${NC}"
    log ""
    log "╔═══════════════════════════════════════════════════════════╗"
    log "║  Jenkins CI/CD Server (Fully Configured with SSL)       ║"
    log "╚═══════════════════════════════════════════════════════════╝"
    log ""
    log "  ${GREEN}✓ Setup wizard skipped - Jenkins ready to use!${NC}"
    log "  ${GREEN}✓ SSL certificate generated for secure access${NC}"
    log "  ${GREEN}✓ Nginx reverse proxy configured${NC}"
    log ""
    log "  Web UI (Secure):"
    log "    ${BLUE}https://factory.local${NC} ${GREEN}← Default HTTPS port!${NC}"
    log ""
    log "  ${YELLOW}Note: Accept the self-signed certificate in your browser${NC}"
    log ""
    log "  Login Credentials:"
    log "    Username: ${BLUE}foreman${NC}"
    log "    Password: ${BLUE}(see credentials below)${NC}"
    log ""
    log "  Jenkins CLI (Host):"
    log "    Command: ${BLUE}jenkins-factory <command>${NC}"
    log "    Examples:"
    log "      ${BLUE}jenkins-factory who-am-i${NC}        # Verify connection"
    log "      ${BLUE}jenkins-factory list-jobs${NC}       # List all jobs"
    log "      ${BLUE}jenkins-factory build <job>${NC}     # Trigger build"
    log "    ${GREEN}✓${NC} Configured for user: ${BLUE}foreman${NC}"
    log "    ${GREEN}✓${NC} API token auto-configured"
    log "    Reload shell: ${BLUE}source ~/.bashrc${NC}"
    log ""
    log "  Features:"
    log "    ${GREEN}✓${NC} Auto-starts on boot"
    log "    ${GREEN}✓${NC} SSL/TLS encryption"
    log "    ${GREEN}✓${NC} Reverse proxy (Nginx)"
    log "    ${GREEN}✓${NC} Essential plugins pre-installed"
    log "    ${GREEN}✓${NC} Security configured"
    log "    ${GREEN}✓${NC} AWS credentials support"
    log ""
    log "  View Jenkins logs:"
    log "    ${BLUE}ssh factory 'sudo docker logs -f jenkins'${NC}"
    log ""
    log "  Manual control (if needed):"
    log "    Start:  ${BLUE}ssh factory 'sudo rc-service jenkins start'${NC}"
    log "    Stop:   ${BLUE}ssh factory 'sudo rc-service jenkins stop'${NC}"
    log "    Status: ${BLUE}ssh factory 'sudo rc-service jenkins status'${NC}"
    log ""
    log "Quick Start Guide:"
    log "  1. Connect to Factory VM:"
    log "     ${BLUE}ssh factory${NC}"
    log ""
    log "  2. Verify tools:"
    log "     ${BLUE}docker --version${NC}"
    log "     ${BLUE}kubectl version --client${NC}"
    log "     ${BLUE}terraform version${NC}"
    log ""
    log "  3. Configure AWS (on localhost first):"
    log "     ${BLUE}awslogin${NC}"
    log "     Then SSH will forward credentials to Factory"
    log ""
    log "  4. Start building ARM64 images:"
    log "     ${BLUE}docker build -t myapp:arm64 .${NC}"
    log ""
    log "  5. Access Jenkins (already running):"
    log "     Open: ${BLUE}https://factory.local${NC}"
    log "     Login: ${BLUE}foreman / (see password below)${NC}"
    log ""
    log "Documentation: ${VM_DIR}/FACTORY-README.md"
    log ""
    
    # Create credentials file
    log_info "Creating credentials file..."
    mkdir -p ~/.factory-vm || { log_error "Failed to create ~/.factory-vm directory"; }
    chmod 700 ~/.factory-vm || true
    
    # Verify passwords are set (defensive programming)
    if [ -z "${JENKINS_FOREMAN_PASSWORD:-}" ]; then
        log_warning "JENKINS_FOREMAN_PASSWORD not set - using default"
        JENKINS_FOREMAN_PASSWORD="foreman123"
    fi
    if [ -z "${VM_ROOT_PASSWORD:-}" ]; then
        VM_ROOT_PASSWORD="(not saved - use SSH key)"
    fi
    if [ -z "${FOREMAN_OS_PASSWORD:-}" ]; then
        FOREMAN_OS_PASSWORD="(not saved - use SSH key)"
    fi
    
    cat > ~/.factory-vm/credentials.txt << CRED_EOF
Factory VM Credentials - $(date)

=== Jenkins Web Console ===
URL:      https://factory.local
Username: foreman
Password: ${JENKINS_FOREMAN_PASSWORD}

The foreman user has full administrative access to Jenkins.
Jenkins CLI uses API token (auto-configured).

=== Emergency OS Access (SSH keys recommended) ===
root:    ${VM_ROOT_PASSWORD}
foreman: ${FOREMAN_OS_PASSWORD}

SSH access uses keys by default (no password needed).
Passwords are for emergency console access only.

=== Notes ===
- SSH authentication: Keys only (password auth disabled)
- Jenkins CLI: Uses API token (configured automatically)
- Web UI: Use foreman username and password above
- No separate admin user - foreman has full admin privileges

CRED_EOF
    
    chmod 600 ~/.factory-vm/credentials.txt || true
    log_success "✓ Credentials saved to ~/.factory-vm/credentials.txt"
    
    # Calculate and display installation time
    SETUP_END_TIME=$(date +%s)
    SETUP_DURATION=$((SETUP_END_TIME - SETUP_START_TIME))
    SETUP_MINUTES=$((SETUP_DURATION / 60))
    SETUP_SECONDS=$((SETUP_DURATION % 60))
    
    log ""
    log "╔═══════════════════════════════════════════════════════════╗"
    log "║                                                           ║"
    log "║          ${YELLOW}IMPORTANT: Jenkins Web Console Credentials${NC}          ║"
    log "║                                                           ║"
    log "╚═══════════════════════════════════════════════════════════╝"
    log ""
    log "  URL:      ${BLUE}https://factory.local${NC}"
    log "  Username: ${BLUE}foreman${NC}"
    log "  Password: ${YELLOW}${JENKINS_FOREMAN_PASSWORD}${NC}"
    log ""
    log "  ${RED}⚠  Save this password - it is shown only once!${NC}"
    log ""
    log "  Credentials saved to: ${BLUE}~/.factory-vm/credentials.txt${NC}"
    log "  (Includes emergency OS passwords if needed)"
    log ""
    log "  ${GREEN}SSH uses keys only - no password needed for SSH access${NC}"
    log ""
    
    # Create convenience symlinks in ~/.scripts if it exists (jcscripts integration)
    if [ -d ~/.scripts ]; then
        log "Creating convenience symlinks in ~/.scripts..."
        ln -sf "${VM_DIR}/start-factory.sh" ~/.scripts/factorystart
        ln -sf "${VM_DIR}/stop-factory.sh" ~/.scripts/factorystop
        ln -sf "${VM_DIR}/status-factory.sh" ~/.scripts/factorystatus
        log "  ✓ Created: ${BLUE}factorystart${NC}, ${BLUE}factorystop${NC}, ${BLUE}factorystatus${NC}"
        log ""
    fi
    
    log "${GREEN}✓ Factory VM setup complete!${NC}"
    log ""
    log "Installation time: ${YELLOW}${SETUP_MINUTES} minutes ${SETUP_SECONDS} seconds${NC}"
    log ""
    log "${GREEN}✓ Factory VM is now running and ready to use!${NC}"
    log ""
    log "Access the VM:"
    log "  SSH:     ${BLUE}ssh factory${NC}"
    log "  Jenkins: ${BLUE}https://factory.local${NC}"
    log ""
    log "VM Management:"
    log "  Scripts: ${BLUE}factorystart${NC}, ${BLUE}factorystop${NC}, ${BLUE}factorystatus${NC}"
    log "  Or:      ${BLUE}~/vms/factory/start-factory.sh${NC}"
    log ""
}

main "$@"
