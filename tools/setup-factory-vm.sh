#!/bin/bash
# Version: 3.0.0 - Modular Architecture (Phase 3.5)

################################################################################
# Factory VM - Fully Automated Setup (Modular)
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
#   ./setup-factory-vm.sh [--auto|-y]
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

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect if we're running from one-liner install (~/ factory-vm/) or from repo
if [ "$(basename "$SCRIPT_DIR")" = "factory-vm" ]; then
    # One-liner install: ~/factory-vm/setup-factory-vm.sh
    PROJECT_ROOT="$SCRIPT_DIR"
    CACHE_DIR="${SCRIPT_DIR}/cache"
else
    # Development/repo: ~/GitProjects/FactoryVM/FactoryVM/tools/setup-factory-vm.sh
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    CACHE_DIR="${PROJECT_ROOT}/cache"
fi

VM_DIR="${HOME}/vms/factory"
VM_NAME="factory"
VM_MEMORY="4G"
VM_CPUS="4"
VM_SSH_PORT="2222"

# Factory VM Configuration
VM_HOSTNAME="factory.local"
VM_USERNAME="foreman"
SSH_KEY_NAME="factory-foreman"

# Disk configuration
SYSTEM_DISK_SIZE="50G"
DATA_DISK_SIZE="50G"
SYSTEM_DISK="${VM_DIR}/${VM_NAME}.qcow2"
DATA_DISK="${VM_DIR}/${VM_NAME}-data.qcow2"

# Alpine configuration
ALPINE_VERSION="3.19"
ALPINE_ARCH="aarch64"

# Cache directory (shared with repository)
CACHE_DIR="${PROJECT_ROOT}/cache"

# Export variables for modules
export SCRIPT_DIR PROJECT_ROOT VM_DIR VM_NAME VM_MEMORY VM_CPUS VM_SSH_PORT
export VM_HOSTNAME VM_USERNAME SSH_KEY_NAME
export SYSTEM_DISK_SIZE DATA_DISK_SIZE SYSTEM_DISK DATA_DISK
export ALPINE_VERSION ALPINE_ARCH CACHE_DIR

################################################################################
# Source Modules
################################################################################

LIB_DIR="${SCRIPT_DIR}/lib"

# Core utilities
source "${LIB_DIR}/common.sh"

# Cache and download management
source "${LIB_DIR}/cache-manager.sh"

# VM lifecycle
source "${LIB_DIR}/vm-lifecycle.sh"

# VM bootstrap and configuration
source "${LIB_DIR}/vm-bootstrap.sh"

# Tool installers
source "${LIB_DIR}/install-base.sh"
source "${LIB_DIR}/install-docker.sh"
source "${LIB_DIR}/install-caddy.sh"
source "${LIB_DIR}/install-k8s-tools.sh"
source "${LIB_DIR}/install-terraform.sh"
source "${LIB_DIR}/install-awscli.sh"
source "${LIB_DIR}/install-jcscripts.sh"
source "${LIB_DIR}/install-jenkins.sh"
source "${LIB_DIR}/configure-jenkins.sh"
source "${LIB_DIR}/install-certificates.sh"

# UI/Documentation
source "${LIB_DIR}/setup-motd.sh"

################################################################################
# Helper Functions (To Be Extracted Later)
################################################################################

offer_configuration_choice() {
    if [ "$AUTO_MODE" = "true" ]; then
        log_info "Auto mode: Using recommended configuration"
        return 0
    fi
    
    log ""
    log "Factory VM Configuration"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "Recommended Settings:"
    log "  Memory: ${VM_MEMORY}"
    log "  CPUs: ${VM_CPUS}"
    log "  System Disk: ${SYSTEM_DISK_SIZE}"
    log "  Data Disk: ${DATA_DISK_SIZE}"
    log ""
    
    read -p "Use recommended settings? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log_success "Using recommended configuration"
    else
        log_info "Custom configuration not yet supported - using recommended"
    fi
}

generate_start_script() {
    log "Generating Factory VM start script..."
    
    local uefi_fw=$(find_uefi_firmware)
    
    cat > "${VM_DIR}/start-factory.sh" << EOF
#!/bin/bash
VM_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DISK="${SYSTEM_DISK}"
DATA_DISK="${DATA_DISK}"
UEFI_FW="${uefi_fw}"
VM_MEMORY="${VM_MEMORY}"
VM_CPUS="${VM_CPUS}"
SSH_PORT="${VM_SSH_PORT}"
PID_FILE="\${VM_DIR}/factory.pid"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -f "\$PID_FILE" ] && sudo kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
    echo -e "\${YELLOW}Factory VM is already running\${NC}"
    echo "  Connect: ssh factory"
    exit 0
fi

if ! grep -q "factory.local" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 factory.local" | sudo tee -a /etc/hosts > /dev/null
fi

echo -e "\${GREEN}Starting Factory VM...\${NC}"

HOST_ARCH=\$(uname -m)
if [ "\$HOST_ARCH" = "aarch64" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    QEMU_ACCEL="-accel kvm"
elif [ "\$HOST_ARCH" = "x86_64" ]; then
    QEMU_ACCEL="-accel tcg"
else
    QEMU_ACCEL="-accel tcg"
fi

touch "\${PID_FILE}"

sudo qemu-system-aarch64 \\
    -M virt \${QEMU_ACCEL} \\
    -cpu cortex-a72 \\
    -smp \${VM_CPUS} \\
    -m \${VM_MEMORY} \\
    -bios \${UEFI_FW} \\
    -drive file="\${SYSTEM_DISK}",if=virtio,format=qcow2 \\
    -drive file="\${DATA_DISK}",if=virtio,format=qcow2 \\
    -device virtio-net-pci,netdev=net0 \\
    -netdev user,id=net0,hostfwd=tcp::\${SSH_PORT}-:22,hostfwd=tcp::443-:443 \\
    -display none \\
    -daemonize \\
    -pidfile "\${PID_FILE}"

echo "✓ Factory VM started"
echo "  SSH: ssh factory"
echo "  Jenkins: https://factory.local"
EOF

    chmod +x "${VM_DIR}/start-factory.sh"
    
    # Create stop script
    cat > "${VM_DIR}/stop-factory.sh" << 'EOF'
#!/bin/bash
PID_FILE="$(dirname "${BASH_SOURCE[0]}")/factory.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "Factory VM is not running"
    exit 0
fi

PID=$(cat "$PID_FILE")
if sudo kill -0 "$PID" 2>/dev/null; then
    echo "Stopping Factory VM..."
    sudo kill "$PID"
    rm -f "$PID_FILE"
    echo "✓ Factory VM stopped"
else
    echo "Factory VM process not found"
    rm -f "$PID_FILE"
fi
EOF

    chmod +x "${VM_DIR}/stop-factory.sh"
    
    # Create status script
    cat > "${VM_DIR}/status-factory.sh" << 'EOF'
#!/bin/bash
################################################################################
# Check Factory VM Status
#
# Shows if the VM is running, accessible, and what services are available
#
################################################################################

# Always use the actual VM directory, not symlink location
VM_DIR="${HOME}/vms/factory"
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
elif ! ps -p "$PID" > /dev/null 2>&1; then
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
    
    # Create convenience symlinks in ~/.scripts if it exists
    if [ -d "${HOME}/.scripts" ]; then
        log_info "Creating convenience links in ~/.scripts..."
        ln -sf "${VM_DIR}/start-factory.sh" "${HOME}/.scripts/factorystart"
        ln -sf "${VM_DIR}/stop-factory.sh" "${HOME}/.scripts/factorystop"
        ln -sf "${VM_DIR}/status-factory.sh" "${HOME}/.scripts/factorystatus"
        log_success "Created: factorystart, factorystop, factorystatus"
    fi
    
    log_success "VM management scripts created"
}

configure_host_ssh() {
    log "Configuring SSH on host..."
    
    local ssh_config="${HOME}/.ssh/config"
    
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    
    if [ -f "$ssh_config" ]; then
        awk '/^# Alpine ARM64 VM/,/^$/{next} /^Host factory$/,/^$/{next} {print}' "$ssh_config" > "${ssh_config}.tmp"
        mv "${ssh_config}.tmp" "$ssh_config"
    else
        touch "$ssh_config"
    fi
    
    chmod 600 "$ssh_config"
    
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

    log_success "SSH config updated (ssh factory)"
}

setup_host_jenkins_cli() {
    log "Setting up Jenkins CLI on host..."
    
    # Create directory for Jenkins CLI jar
    mkdir -p ~/.java/jars
    
    # Copy Jenkins CLI jar from VM
    scp -i "$VM_SSH_PRIVATE_KEY" -P "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        foreman@localhost:/usr/local/share/jenkins/jenkins-cli.jar \
        ~/.java/jars/jenkins-cli-factory.jar 2>/dev/null || {
        log_warning "Could not copy Jenkins CLI jar - will be downloaded on first use"
    }
    
    # Get and cache the API token
    local api_token
    api_token=$(ssh -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        foreman@localhost "sudo docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null" | tr -d '\n\r')
    
    if [ -n "$api_token" ]; then
        echo "$api_token" > ~/.jenkins-factory-token
        chmod 600 ~/.jenkins-factory-token
        log_success "API token cached to ~/.jenkins-factory-token"
    fi
    
    # Add jenkins-factory function to .bashrc if not already present
    if ! grep -q "jenkins-factory()" ~/.bashrc 2>/dev/null; then
        log_info "Adding jenkins-factory function to ~/.bashrc..."
        
        cat >> ~/.bashrc << 'JENKINS_BASHRC'

################################################################################
# Jenkins Factory CLI Helper
################################################################################
# Usage:
#   jenkins-factory help                    # Show available commands
#   jenkins-factory who-am-i                # Verify authentication
#   jenkins-factory list-jobs               # List all jobs
#   jenkins-factory build <job-name>        # Trigger a build
################################################################################

jenkins-factory() {
    local api_token
    
    # Load token from cache or fetch new one
    if [ -f ~/.jenkins-factory-token ]; then
        api_token=$(cat ~/.jenkins-factory-token)
    else
        api_token=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p 2222 foreman@localhost \
            "sudo docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt 2>/dev/null" 2>/dev/null | tr -d '\n\r')
        if [ -n "$api_token" ]; then
            echo "$api_token" > ~/.jenkins-factory-token
            chmod 600 ~/.jenkins-factory-token
        fi
    fi
    
    if [ -z "$api_token" ]; then
        echo "ERROR: Could not get Jenkins API token" >&2
        echo "Make sure Factory VM is running: factorystart" >&2
        return 1
    fi
    
    # Download CLI jar if not present
    if [ ! -f ~/.java/jars/jenkins-cli-factory.jar ]; then
        echo "Downloading Jenkins CLI jar..."
        mkdir -p ~/.java/jars
        scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -P 2222 foreman@localhost:/usr/local/share/jenkins/jenkins-cli.jar \
            ~/.java/jars/jenkins-cli-factory.jar 2>/dev/null || {
            echo "ERROR: Could not download Jenkins CLI jar" >&2
            return 1
        }
    fi
    
    java -jar ~/.java/jars/jenkins-cli-factory.jar \
        -s https://factory.local \
        -auth foreman:"$api_token" \
        -webSocket \
        "$@"
}

JENKINS_BASHRC
        
        log_success "jenkins-factory function added to ~/.bashrc"
        log_info "Reload with: source ~/.bashrc"
    else
        log_info "jenkins-factory function already exists in ~/.bashrc"
        # Update the token file
        if [ -n "$api_token" ]; then
            echo "$api_token" > ~/.jenkins-factory-token
            chmod 600 ~/.jenkins-factory-token
        fi
    fi
}

create_documentation() {
    log "Creating documentation..."
    
    cat > "${VM_DIR}/README.md" << 'EOF'
# Factory VM - ARM64 Build Environment

## Quick Start

```bash
# Start VM
./start-factory.sh

# Connect
ssh factory

# Stop VM
./stop-factory.sh
```

## Installed Tools

- Docker, Docker Compose
- Kubernetes (kubectl, Helm)
- Terraform, AWS CLI
- Jenkins (https://factory.local)
- Git, Node.js, Python, Java
- jcscripts collection

## Credentials

See `credentials.txt` for passwords and tokens.

## Documentation

Full documentation at: https://github.com/jcgarcia/factory-vm
EOF

    # Save credentials
    cat > "${VM_DIR}/credentials.txt" << EOF
Factory VM Credentials
Generated: $(date)

VM Access:
  SSH: ssh factory
  User: foreman
  Password: ${FOREMAN_OS_PASSWORD}

Jenkins:
  URL: https://factory.local
  User: foreman
  Password: ${JENKINS_FOREMAN_PASSWORD}

Note: Passwords are auto-generated for security.
      Keep this file secure!
EOF

    chmod 600 "${VM_DIR}/credentials.txt"
    
    log_success "Documentation created"
}

################################################################################
# Main Installation Flow
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

    SETUP_START_TIME=$(date +%s)
    
    log "Starting Factory VM setup..."
    log ""
    
    # Configuration
    offer_configuration_choice
    
    # Generate secure passwords
    log_info "Generating secure passwords..."
    VM_ROOT_PASSWORD=$(generate_secure_password)
    FOREMAN_OS_PASSWORD=$(generate_secure_password)
    JENKINS_FOREMAN_PASSWORD=$(generate_secure_password)
    
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
    cache_all_tools
    cache_all_plugins
    
    # Install Alpine
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "  Step 1: Alpine Linux Installation"
    log "═══════════════════════════════════════════════════════════"
    start_vm_for_install
    
    # Generate management scripts
    generate_start_script
    
    # Configure VM (this calls all installer modules)
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "  Step 2: Configure Factory VM"
    log "═══════════════════════════════════════════════════════════"
    configure_installed_vm
    
    # Host configuration
    configure_host_ssh
    install_certificates_on_host
    setup_host_jenkins_cli
    create_documentation
    
    # Calculate installation time
    SETUP_END_TIME=$(date +%s)
    SETUP_DURATION=$((SETUP_END_TIME - SETUP_START_TIME))
    SETUP_MINUTES=$((SETUP_DURATION / 60))
    SETUP_SECONDS=$((SETUP_DURATION % 60))
    
    log ""
    log "╔═══════════════════════════════════════════════════════════╗"
    log "║                                                           ║"
    log "║        ✓ Factory VM Setup Complete!                      ║"
    log "║                                                           ║"
    log "╚═══════════════════════════════════════════════════════════╝"
    log ""
    log "${GREEN}Factory VM is ready for use!${NC}"
    log ""
    log "Installation Time: ${SETUP_MINUTES}m ${SETUP_SECONDS}s"
    log ""
    log "Connection:"
    log "  ${BLUE}ssh factory${NC}"
    log ""
    log "VM Management:"
    log "  Start:  ${BLUE}~/vms/factory/start-factory.sh${NC}"
    log "  Stop:   ${BLUE}~/vms/factory/stop-factory.sh${NC}"
    log ""
    log "Jenkins CI/CD Server:"
    log "  ${BLUE}https://factory.local${NC}"
    log "  User: ${BLUE}foreman${NC}"
    log "  Password: ${BLUE}(see ~/vms/factory/credentials.txt)${NC}"
    log ""
    log "Credentials saved to: ${BLUE}~/vms/factory/credentials.txt${NC}"
    log ""
}

# Run main installation
main "$@"
