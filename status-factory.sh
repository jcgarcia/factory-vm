#!/bin/bash
#
# Check Factory VM status
#

VM_DIR="${HOME}/vms/factory"

if [ ! -d "$VM_DIR" ]; then
    echo "Factory VM: NOT INSTALLED"
    echo "Run ./factory-vm/setup-factory-vm.sh to create it"
    exit 1
fi

if [ -f "$VM_DIR/factory.pid" ] && kill -0 $(cat "$VM_DIR/factory.pid") 2>/dev/null; then
    PID=$(cat "$VM_DIR/factory.pid")
    echo "Factory VM: RUNNING"
    echo "  PID: $PID"
    echo "  SSH: ssh factory"
    
    # Try to get info from VM
    if ssh -i ~/.ssh/factory-foreman \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=2 \
        -p 2222 foreman@localhost 'hostname && uname -r' 2>/dev/null; then
        echo "  Status: SSH accessible"
    else
        echo "  Status: Booting or SSH not ready"
    fi
else
    echo "Factory VM: STOPPED"
    echo "Start with: ./factory-vm/start-factory.sh"
fi
