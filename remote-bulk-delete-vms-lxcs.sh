#!/bin/bash

# List of Proxmox node IPs
# NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
NODES=(136.204.36.19)

for NODE in "${NODES[@]}"; do
    echo "Checking VMs and LXCs on $NODE..."

    # Fetch VM/LXC info (suppress invalid group warnings)
    VM_LIST=$(ssh root@$NODE "qm list 2> >(grep -v 'invalid group member' >&2)")
    CT_LIST=$(ssh root@$NODE "pct list 2> >(grep -v 'invalid group member' >&2)")

    # Format options: ID Name [type]
    OPTIONS=()
    while read -r ID NAME REST; do
        [[ "$ID" == "VMID" || -z "$ID" ]] && continue
        DESC=$(ssh root@$NODE "qm config $ID | grep -i description | cut -d ' ' -f2-" 2>/dev/null | cut -d '<' -f1)
        POOL=$(ssh root@$NODE "pvesh get /nodes/$(hostname -s)/qemu/$ID/config --output-format=json" 2>/dev/null | jq -r '.pool // empty')
        DISPLAY="$ID: $NAME"
        [[ -n "$DESC" ]] && DISPLAY+=" - $DESC"
        [[ -n "$POOL" ]] && DISPLAY+=" [Pool: $POOL]"
        OPTIONS+=("$ID" "$DISPLAY" "OFF")
    done <<< "$VM_LIST"

    while read -r ID NAME STATUS IP REST; do
        [[ "$ID" == "VMID" || -z "$ID" ]] && continue
        DESC=$(ssh root@$NODE "pct config $ID | grep -i description | cut -d ' ' -f2-" 2>/dev/null | cut -d '<' -f1)
        POOL=$(ssh root@$NODE "pvesh get /nodes/$(hostname -s)/lxc/$ID/config --output-format=json" 2>/dev/null | jq -r '.pool // empty')
        DISPLAY="$ID: $NAME"
        [[ -n "$DESC" ]] && DISPLAY+=" - $DESC"
        [[ -n "$POOL" ]] && DISPLAY+=" [Pool: $POOL]"
        OPTIONS+=("$ID" "$DISPLAY" "OFF")
    done <<< "$CT_LIST"

    if [[ ${#OPTIONS[@]} -eq 0 ]]; then
        echo "No VMs or LXCs found on $NODE."
        continue
    fi

    SELECTION=$(whiptail --title "Delete from $NODE" --checklist "Select VMs or LXCs to DELETE on $NODE:" 20 80 12 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$SELECTION" ]]; then
        echo "No selection made for $NODE. Skipping..."
        continue
    fi

    for ID in $SELECTION; do
        ID=$(echo $ID | tr -d '"')
        echo "Attempting to delete VM or LXC $ID on $NODE..."
        ssh root@$NODE "qm status $ID" &>/dev/null
        if [[ $? -eq 0 ]]; then
            ssh root@$NODE "qm shutdown $ID --timeout 30 && qm destroy $ID --purge"
        else
            ssh root@$NODE "pct shutdown $ID --timeout 30 && pct destroy $ID"
        fi
    done

done

echo "Bulk deletion process completed."
