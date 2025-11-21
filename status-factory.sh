#!/bin/bash
#
# Check Factory VM status
#

VM_DIR="${HOME}/vms/factory"

if [ ! -d "$VM_DIR" ]; then
    echo "Factory VM Status"
    echo "================="
    echo ""
    echo "✗ VM is not installed"
    echo ""
    echo "Install with:"
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh)"
    exit 1
fi

# Check if PID file exists and process is running (works even if running as root)
if [ -f "$VM_DIR/factory.pid" ]; then
    PID=$(cat "$VM_DIR/factory.pid" 2>/dev/null)
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
        echo "Factory VM Status"
        echo "================="
        echo ""
        echo "✓ VM is running"
        echo "  PID: $PID"
        echo "  SSH: ssh factory"
        echo ""
        
        # Try to get info from VM
        if ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=2 \
            -p 2222 foreman@localhost 'echo "  Hostname: $(hostname)" && echo "  Kernel: $(uname -r)"' 2>/dev/null; then
            echo "  Status: SSH accessible ✓"
        else
            echo "  Status: Booting or SSH not ready..."
        fi
        exit 0
    fi
fi

echo "Factory VM Status"
echo "================="
echo ""
echo "✗ VM is not running"
echo ""
echo "Start the VM with:"
echo "  ${VM_DIR}/start-factory.sh"
