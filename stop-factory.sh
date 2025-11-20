#!/bin/bash
#
# Stop Factory VM
#

set -e

VM_DIR="${HOME}/vms/factory"

# Check if VM exists
if [ ! -d "$VM_DIR" ]; then
    echo "ERROR: Factory VM not found at $VM_DIR"
    exit 1
fi

# Check if running
if [ ! -f "$VM_DIR/factory.pid" ]; then
    echo "Factory VM is not running (no PID file)"
    exit 0
fi

PID=$(cat "$VM_DIR/factory.pid")

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Factory VM is not running (stale PID file)"
    rm -f "$VM_DIR/factory.pid"
    exit 0
fi

echo "Stopping Factory VM (PID: $PID)..."

# Try graceful shutdown via SSH first
if command -v ssh >/dev/null 2>&1; then
    ssh -i ~/.ssh/factory-foreman \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=2 \
        -p 2222 root@localhost 'poweroff' 2>/dev/null || true
    
    # Wait up to 10 seconds for graceful shutdown
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "Factory VM stopped gracefully"
            rm -f "$VM_DIR/factory.pid"
            exit 0
        fi
        sleep 1
    done
fi

# Force kill if still running
if kill -0 "$PID" 2>/dev/null; then
    echo "Forcing VM shutdown..."
    kill -9 "$PID"
    sleep 1
fi

rm -f "$VM_DIR/factory.pid" 2>/dev/null || true
echo "Factory VM stopped"
