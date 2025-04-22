#!/bin/bash

# List of Proxmox node IPs to iterate over
# NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
NODES=(136.204.36.19)


for NODE in "${NODES[@]}"; do
    echo ""
    echo "Checking VMs and LXCs on $NODE..."

    # Get the VM/LXC list and format for dialog
    VM_LIST=$(ssh root@$NODE "qm list 2> >(grep -v 'invalid group member' >&2)" | awk 'NR>1 {print $1 " \"" $2 "\""}')
    LXC_LIST=$(ssh root@$NODE "pct list" | awk 'NR>1 {print $1 " \"" $2 "\""}')
    ALL_LIST=$(printf "%s\n%s" "$VM_LIST" "$LXC_LIST")

    if [[ -z "$ALL_LIST" ]]; then
        echo "No VMs or LXCs found on $NODE."
        continue
    fi

    # Use dialog to select which to delete
    SELECTED=$(echo "$ALL_LIST" | dialog --stdout --separate-output --checklist "Select VMs or LXCs to DELETE on $NODE:" 20 70 15)

    if [[ -z "$SELECTED" ]]; then
        echo "No selection made for $NODE. Skipping..."
        continue
    fi

    for VMID in $SELECTED; do
        if [[ "$VMID" =~ ^[0-9]+$ ]]; then
            echo "Deleting $VMID on $NODE..."
            ssh root@$NODE "
                if qm status $VMID &>/dev/null; then
                    qm shutdown $VMID --timeout 30
                    qm destroy $VMID --purge
                elif pct status $VMID &>/dev/null; then
                    pct shutdown $VMID
                    pct destroy $VMID
                else
                    echo 'VMID $VMID not found on $NODE.'
                fi"
        else
            echo "Invalid VMID: $VMID - skipping"
        fi
    done
done
