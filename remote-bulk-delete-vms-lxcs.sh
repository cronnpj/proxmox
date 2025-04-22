#!/bin/bash

# Proxmox cluster IPs
# NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
NODES=(136.204.36.19)

for NODE in "${NODES[@]}"; do
    echo "Checking VMs and LXCs on $NODE..."

    VM_LIST=$(ssh root@$NODE \
        "qm list | tail -n +2 | awk '{print \$1}' && pct list | tail -n +2 | awk '{print \$1}'")

    MENU_ITEMS=()

    for ID in $VM_LIST; do
        if ssh root@$NODE qm status $ID &>/dev/null; then
            NAME=$(ssh root@$NODE qm config $ID | grep -m1 '^name:' | cut -d ' ' -f2-)
            DESC=$(ssh root@$NODE qm config $ID | grep -m1 '^description:' | cut -d ' ' -f2- | sed 's/<[^>]*>//g')
            POOL=$(ssh root@$NODE grep -l "^$ID$" /etc/pve/pool/*/vmid | sed 's#.*/##' | head -n1)
        else
            NAME=$(ssh root@$NODE pct config $ID | grep -m1 '^hostname:' | cut -d ' ' -f2-)
            DESC=$(ssh root@$NODE pct config $ID | grep -m1 '^description:' | cut -d ' ' -f2- | sed 's/<[^>]*>//g')
            POOL=$(ssh root@$NODE grep -l "^$ID$" /etc/pve/pool/*/lxc | sed 's#.*/##' | head -n1)
        fi

        LABEL="$ID - $NAME"
        [[ -n "$DESC" ]] && LABEL+=" :: $DESC"
        [[ -n "$POOL" ]] && LABEL+=" [Pool: $POOL]"

        MENU_ITEMS+=("$ID" "$LABEL" off)
    done

    if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
        echo "No VMs or LXCs found on $NODE."
        continue
    fi

    CHOICES=$(dialog --separate-output --checklist "Select VMs or LXCs to DELETE on $NODE:" 20 80 15 \${MENU_ITEMS[@]} 3>&1 1>&2 2>&3)

    for ID in $CHOICES; do
        if ssh root@$NODE qm status $ID &>/dev/null; then
            echo "Deleting VM $ID on $NODE..."
            ssh root@$NODE "qm stop $ID && qm destroy $ID --purge --destroy-unreferenced-disks 1"
        else
            echo "Deleting LXC $ID on $NODE..."
            ssh root@$NODE "pct shutdown $ID && pct destroy $ID"
        fi
    done

done

echo "Bulk deletion process complete."
