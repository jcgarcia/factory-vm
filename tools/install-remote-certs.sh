#!/bin/bash
#
# install-remote-certs.sh - Install Factory VM certificates from a remote server
#
# This script connects to a remote server running Factory VM, downloads the
# Caddy CA certificates, and installs them on the local system so you can
# access https://factory.local without certificate warnings.
#
# Usage:
#   ./install-remote-certs.sh <ssh-host>
#
# Example:
#   ./install-remote-certs.sh lcognito
#   ./install-remote-certs.sh user@remote-server.com
#
# Prerequisites:
#   - SSH access to the remote server
#   - Factory VM installed and running on the remote server
#   - sudo access on localhost (for certificate installation)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <ssh-host>"
    echo ""
    echo "Example:"
    echo "  $0 lcognito"
    echo "  $0 user@remote-server.com"
    echo ""
    echo "This script downloads Factory VM certificates from a remote server"
    echo "and installs them on your local system."
    exit 1
fi

SSH_HOST="$1"
CERT_DIR="$HOME/.factory-certs"
REMOTE_CERT_DIR="~/vms/factory"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Factory VM Remote Certificate Installer                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Test SSH connection
info "Testing SSH connection to ${SSH_HOST}..."
if ! ssh -o ConnectTimeout=10 "$SSH_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
    error "Cannot connect to ${SSH_HOST}. Check your SSH configuration."
fi
success "SSH connection OK"

# Check if Factory VM certificates exist on remote
info "Checking for Factory VM certificates on remote server..."
if ! ssh "$SSH_HOST" "test -f ${REMOTE_CERT_DIR}/caddy-root-ca.crt" 2>/dev/null; then
    error "Factory VM certificates not found on ${SSH_HOST}. Is Factory VM installed?"
fi
success "Certificates found on remote server"

# Create local certificate directory
mkdir -p "$CERT_DIR"

# Download certificates
info "Downloading certificates from ${SSH_HOST}..."
scp -q "${SSH_HOST}:${REMOTE_CERT_DIR}/caddy-root-ca.crt" "$CERT_DIR/" || error "Failed to download root certificate"
scp -q "${SSH_HOST}:${REMOTE_CERT_DIR}/caddy-intermediate-ca.crt" "$CERT_DIR/" || error "Failed to download intermediate certificate"
success "Certificates downloaded to ${CERT_DIR}"

# Detect OS and install certificates
info "Detecting operating system..."
OS_TYPE="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|pop|linuxmint)
            OS_TYPE="debian"
            ;;
        fedora|rhel|centos|rocky|alma)
            OS_TYPE="redhat"
            ;;
        arch|manjaro)
            OS_TYPE="arch"
            ;;
        alpine)
            OS_TYPE="alpine"
            ;;
    esac
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
fi

info "Detected OS type: ${OS_TYPE}"

# Install to system trust store
info "Installing certificates to system trust store..."

case "$OS_TYPE" in
    debian)
        # Ubuntu/Debian
        CERT_DEST="/usr/local/share/ca-certificates/factory-vm"
        sudo mkdir -p "$CERT_DEST"
        
        # Remove old certificates if present
        sudo rm -f "$CERT_DEST"/*.crt 2>/dev/null || true
        
        # Copy new certificates
        sudo cp "$CERT_DIR/caddy-root-ca.crt" "$CERT_DEST/factory-caddy-root.crt"
        sudo cp "$CERT_DIR/caddy-intermediate-ca.crt" "$CERT_DEST/factory-caddy-intermediate.crt"
        
        # Update certificate store
        sudo update-ca-certificates
        success "Certificates installed to system trust store"
        ;;
        
    redhat)
        # RHEL/Fedora/CentOS
        CERT_DEST="/etc/pki/ca-trust/source/anchors"
        sudo cp "$CERT_DIR/caddy-root-ca.crt" "$CERT_DEST/factory-caddy-root.crt"
        sudo cp "$CERT_DIR/caddy-intermediate-ca.crt" "$CERT_DEST/factory-caddy-intermediate.crt"
        sudo update-ca-trust
        success "Certificates installed to system trust store"
        ;;
        
    arch)
        # Arch Linux
        sudo trust anchor --store "$CERT_DIR/caddy-root-ca.crt"
        sudo trust anchor --store "$CERT_DIR/caddy-intermediate-ca.crt"
        success "Certificates installed to system trust store"
        ;;
        
    alpine)
        # Alpine Linux
        sudo cp "$CERT_DIR/caddy-root-ca.crt" /usr/local/share/ca-certificates/factory-caddy-root.crt
        sudo cp "$CERT_DIR/caddy-intermediate-ca.crt" /usr/local/share/ca-certificates/factory-caddy-intermediate.crt
        sudo update-ca-certificates
        success "Certificates installed to system trust store"
        ;;
        
    macos)
        # macOS
        info "Installing to macOS Keychain (you may be prompted for your password)..."
        sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_DIR/caddy-root-ca.crt"
        sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_DIR/caddy-intermediate-ca.crt"
        success "Certificates installed to macOS Keychain"
        ;;
        
    *)
        warn "Unknown OS type. Certificates downloaded to ${CERT_DIR} but not installed."
        warn "Please install them manually to your system's trust store."
        ;;
esac

# Install to browser certificate databases (Linux only)
if [[ "$OS_TYPE" != "macos" && "$OS_TYPE" != "unknown" ]]; then
    info "Installing to browser certificate databases..."
    
    # Check if certutil is available
    if command -v certutil &> /dev/null; then
        BROWSER_PROFILES_FOUND=0
        
        # Find all browser certificate databases
        for CERT_DB_DIR in \
            "$HOME/.pki/nssdb" \
            "$HOME/.mozilla/firefox"/*.default* \
            "$HOME/.mozilla/firefox"/*.default-release* \
            "$HOME/snap/firefox/common/.mozilla/firefox"/*.default* \
            "$HOME/.config/chromium"*/Default \
            "$HOME/.config/google-chrome"*/Default \
            "$HOME/.config/BraveSoftware/Brave-Browser"*/Default \
            "$HOME/.config/microsoft-edge"*/Default
        do
            if [ -d "$CERT_DB_DIR" ]; then
                # Check if it's an NSS database
                if [ -f "$CERT_DB_DIR/cert9.db" ] || [ -f "$CERT_DB_DIR/cert8.db" ]; then
                    # Remove old certificates
                    certutil -D -n "Factory Caddy Root CA" -d sql:"$CERT_DB_DIR" 2>/dev/null || true
                    certutil -D -n "Factory Caddy Intermediate CA" -d sql:"$CERT_DB_DIR" 2>/dev/null || true
                    
                    # Add new certificates
                    certutil -A -n "Factory Caddy Root CA" -t "TC,," -i "$CERT_DIR/caddy-root-ca.crt" -d sql:"$CERT_DB_DIR" 2>/dev/null && \
                    certutil -A -n "Factory Caddy Intermediate CA" -t "TC,," -i "$CERT_DIR/caddy-intermediate-ca.crt" -d sql:"$CERT_DB_DIR" 2>/dev/null && \
                    BROWSER_PROFILES_FOUND=$((BROWSER_PROFILES_FOUND + 1))
                fi
            fi
        done
        
        if [ $BROWSER_PROFILES_FOUND -gt 0 ]; then
            success "Certificates installed to ${BROWSER_PROFILES_FOUND} browser profile(s)"
            info "Restart your browser(s) to apply changes"
        else
            warn "No browser certificate databases found"
        fi
    else
        warn "certutil not found - skipping browser certificate installation"
        info "Install libnss3-tools (Debian/Ubuntu) or nss-tools (RHEL/Fedora) for browser support"
    fi
fi

# Get remote server IP for /etc/hosts
info "Getting remote server IP address..."
REMOTE_IP=$(ssh "$SSH_HOST" "hostname -I | awk '{print \$1}'" 2>/dev/null)

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Certificate Installation Complete!                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
success "Certificates installed successfully"
echo ""
echo "Next steps:"
echo ""
echo "1. Add this line to your /etc/hosts file:"
echo ""
echo "   ${REMOTE_IP}    factory.local"
echo ""
echo "   Run this command:"
echo "   echo '${REMOTE_IP}    factory.local' | sudo tee -a /etc/hosts"
echo ""
echo "2. Restart your browser to apply certificate changes"
echo ""
echo "3. Access Jenkins at: https://factory.local"
echo ""
