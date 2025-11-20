#!/bin/bash
#
# Start Factory VM
#

set -e

VM_DIR="${HOME}/vms/factory"
VM_SSH_PORT=2222
JENKINS_HTTPS_PORT=8443
JENKINS_HTTP_PORT=8080

# Add factory.local to /etc/hosts if not already there
if ! grep -q "factory.local" /etc/hosts; then
    echo "Adding factory.local to /etc/hosts..."
    echo "127.0.0.1 factory.local" | sudo tee -a /etc/hosts > /dev/null
    echo "✓ factory.local added to /etc/hosts"
fi

# Check if VM exists
if [ ! -d "$VM_DIR" ]; then
    echo "ERROR: Factory VM not found at $VM_DIR"
    echo "Run ./factory-vm/setup-factory-vm.sh to create it"
    exit 1
fi

# Check if already running
if [ -f "$VM_DIR/factory.pid" ] && kill -0 $(cat "$VM_DIR/factory.pid") 2>/dev/null; then
    echo "Factory VM is already running (PID: $(cat "$VM_DIR/factory.pid"))"
    exit 0
fi

# Determine QEMU acceleration
host_arch=$(uname -m)
qemu_accel=""

if [ "$host_arch" = "aarch64" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    qemu_accel="-accel kvm"
    echo "Starting Factory VM with KVM acceleration..."
else
    qemu_accel="-accel tcg"
    echo "Starting Factory VM with TCG emulation (slower)..."
fi

# Start VM
qemu-system-aarch64 \
    -M virt $qemu_accel \
    -cpu cortex-a72 -smp 4 -m 4G \
    -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    -drive file="$VM_DIR/factory.qcow2",if=virtio,format=qcow2 \
    -drive file="$VM_DIR/factory-data.qcow2",if=virtio,format=qcow2 \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::${VM_SSH_PORT}-:22,hostfwd=tcp::${JENKINS_HTTPS_PORT}-:443,hostfwd=tcp::${JENKINS_HTTP_PORT}-:80 \
    -display none \
    -daemonize \
    -pidfile "$VM_DIR/factory.pid"

echo "Factory VM started successfully"
echo "  SSH: ssh factory"
echo "  Jenkins: https://factory.local (port ${JENKINS_HTTPS_PORT})"
echo "  PID: $(cat "$VM_DIR/factory.pid")"
