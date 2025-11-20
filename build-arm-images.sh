#!/bin/bash

################################################################################
# Build ARM64 Docker Images in VM
#
# This script builds ARM64 Docker images inside the Alpine ARM64 VM,
# then transfers them to the host for pushing to ECR.
#
# Usage:
#   ./factory-vm/build-arm-images.sh [--component COMPONENT] [--tag TAG]
#
# Components: backend, frontend, android, all
# Default tag: latest
#
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_SSH_PORT="2222"
VM_USERNAME="alpine"
VM_HOST="localhost"
VM_PROJECT_DIR="/home/alpine/fintech"
BUILD_COMPONENT="${1:-all}"
IMAGE_TAG="${2:-latest}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[BUILD-ARM]${NC} $*"
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
# SSH Helper
################################################################################

vm_ssh() {
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -p "$VM_SSH_PORT" \
        "${VM_USERNAME}@${VM_HOST}" \
        "$@"
}

vm_scp() {
    scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -P "$VM_SSH_PORT" \
        "$@"
}

################################################################################
# Check VM
################################################################################

check_vm() {
    log "Checking VM status..."
    
    if ! "${SCRIPT_DIR}/check-factory-vm.sh" --quick; then
        log_error "VM is not ready"
        log_info "Run: ${SCRIPT_DIR}/setup-factory-vm.sh"
        exit 1
    fi
    
    log "  ✓ VM is ready"
}

################################################################################
# Sync Project to VM
################################################################################

sync_project_to_vm() {
    log "Syncing project files to VM..."
    
    # Create project directory in VM
    vm_ssh "mkdir -p ${VM_PROJECT_DIR}"
    
    # Sync only necessary files (exclude node_modules, .git, etc.)
    log "  Transferring files..."
    rsync -az \
        --delete \
        --exclude 'node_modules' \
        --exclude '.git' \
        --exclude 'dist' \
        --exclude 'build' \
        --exclude '.next' \
        --exclude 'coverage' \
        --exclude '*.log' \
        --exclude '.env' \
        --exclude '.deployment-state' \
        --exclude '.bootstrap-state' \
        -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p ${VM_SSH_PORT}" \
        "${PROJECT_ROOT}/FinTechApp/" \
        "${VM_USERNAME}@${VM_HOST}:${VM_PROJECT_DIR}/"
    
    log "  ✓ Project synced to VM"
}

################################################################################
# Build Backend Image
################################################################################

build_backend() {
    log "Building backend ARM64 image..."
    
    vm_ssh "cd ${VM_PROJECT_DIR}/backend && docker build -t fintech-backend:${IMAGE_TAG}-arm64 -f Dockerfile ."
    
    log "  ✓ Backend image built: fintech-backend:${IMAGE_TAG}-arm64"
}

################################################################################
# Build Frontend Image
################################################################################

build_frontend() {
    log "Building frontend ARM64 image..."
    
    vm_ssh "cd ${VM_PROJECT_DIR}/frontend && docker build -t fintech-frontend:${IMAGE_TAG}-arm64 -f Dockerfile ."
    
    log "  ✓ Frontend image built: fintech-frontend:${IMAGE_TAG}-arm64"
}

################################################################################
# Build Android Image
################################################################################

build_android() {
    log "Building Android build environment ARM64 image..."
    
    if [ ! -f "${PROJECT_ROOT}/android/Dockerfile" ]; then
        log_warning "Android Dockerfile not found, skipping"
        return 0
    fi
    
    vm_ssh "cd ${VM_PROJECT_DIR}/android && docker build -t fintech-android-builder:${IMAGE_TAG}-arm64 -f Dockerfile ."
    
    log "  ✓ Android builder image built: fintech-android-builder:${IMAGE_TAG}-arm64"
}

################################################################################
# Save and Transfer Images
################################################################################

save_and_transfer_image() {
    local image_name="$1"
    local tar_name="${image_name/:/-}"
    tar_name="${tar_name//\//-}.tar.gz"
    
    log "Saving ${image_name}..."
    
    # Save image in VM
    vm_ssh "docker save ${image_name} | gzip > /tmp/${tar_name}"
    
    # Transfer to host
    log "  Transferring to host..."
    vm_scp "${VM_USERNAME}@${VM_HOST}:/tmp/${tar_name}" "${PROJECT_ROOT}/factory-vm/${tar_name}"
    
    # Clean up on VM
    vm_ssh "rm /tmp/${tar_name}"
    
    log "  ✓ Image saved: factory-vm/${tar_name}"
}

################################################################################
# Load Image on Host
################################################################################

load_image_on_host() {
    local tar_name="$1"
    
    log "Loading ${tar_name} on host..."
    
    if command -v docker &>/dev/null; then
        docker load < "${PROJECT_ROOT}/factory-vm/${tar_name}"
        log "  ✓ Image loaded into host Docker"
    else
        log_warning "Docker not available on host, image saved at: factory-vm/${tar_name}"
        log_info "Load manually with: docker load < factory-vm/${tar_name}"
    fi
}

################################################################################
# Display Image Info
################################################################################

display_image_info() {
    log "Checking built images in VM..."
    
    echo ""
    echo "ARM64 Images built:"
    echo "─────────────────────────────────────────────────────────"
    vm_ssh "docker images --filter 'reference=fintech-*:*-arm64' --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'"
    echo "─────────────────────────────────────────────────────────"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    cat << 'BANNER'
╔═══════════════════════════════════════════════════════════╗
║        Build ARM64 Docker Images                         ║
╚═══════════════════════════════════════════════════════════╝

BANNER

    # Parse arguments
    case "${BUILD_COMPONENT}" in
        backend|frontend|android|all)
            ;;
        *)
            log_error "Invalid component: ${BUILD_COMPONENT}"
            log_info "Valid components: backend, frontend, android, all"
            exit 1
            ;;
    esac
    
    log "Build configuration:"
    log "  Component: ${BUILD_COMPONENT}"
    log "  Tag: ${IMAGE_TAG}"
    log ""
    
    check_vm
    sync_project_to_vm
    
    # Build requested components
    case "${BUILD_COMPONENT}" in
        backend)
            build_backend
            save_and_transfer_image "fintech-backend:${IMAGE_TAG}-arm64"
            load_image_on_host "fintech-backend-${IMAGE_TAG}-arm64.tar.gz"
            ;;
        frontend)
            build_frontend
            save_and_transfer_image "fintech-frontend:${IMAGE_TAG}-arm64"
            load_image_on_host "fintech-frontend-${IMAGE_TAG}-arm64.tar.gz"
            ;;
        android)
            build_android
            save_and_transfer_image "fintech-android-builder:${IMAGE_TAG}-arm64"
            load_image_on_host "fintech-android-builder-${IMAGE_TAG}-arm64.tar.gz"
            ;;
        all)
            build_backend
            build_frontend
            build_android
            
            log ""
            log "Saving and transferring all images..."
            save_and_transfer_image "fintech-backend:${IMAGE_TAG}-arm64"
            save_and_transfer_image "fintech-frontend:${IMAGE_TAG}-arm64"
            if vm_ssh "docker images -q fintech-android-builder:${IMAGE_TAG}-arm64" | grep -q .; then
                save_and_transfer_image "fintech-android-builder:${IMAGE_TAG}-arm64"
            fi
            
            log ""
            log "Loading images on host..."
            load_image_on_host "fintech-backend-${IMAGE_TAG}-arm64.tar.gz"
            load_image_on_host "fintech-frontend-${IMAGE_TAG}-arm64.tar.gz"
            if [ -f "${PROJECT_ROOT}/factory-vm/fintech-android-builder-${IMAGE_TAG}-arm64.tar.gz" ]; then
                load_image_on_host "fintech-android-builder-${IMAGE_TAG}-arm64.tar.gz"
            fi
            ;;
    esac
    
    display_image_info
    
    log ""
    log "✓ ARM64 build complete!"
    log ""
    log "Next steps:"
    log "  1. Tag images for ECR:"
    log "     docker tag fintech-backend:${IMAGE_TAG}-arm64 \$ECR_REGISTRY/fintech-backend:${IMAGE_TAG}-arm64"
    log "  2. Push to ECR:"
    log "     docker push \$ECR_REGISTRY/fintech-backend:${IMAGE_TAG}-arm64"
    log "  3. Update Kubernetes to use ARM64 images"
    log ""
}

main "$@"
