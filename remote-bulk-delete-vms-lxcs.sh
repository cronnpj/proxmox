#!/bin/bash

# Node IPs
#NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
NODES=(136.204.36.19)

for NODE in "${NODES[@]}"; do
    echo "Checking VMs and LXCs on $NODE..."

    # Get list of VMs and LXCs with ID, name, and pool, filter out the header, skip any lines without a valid VMID
    VM_LIST=$(ssh root@$NODE 'qm list 2> >(grep -v "invalid group member" >&2)' | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' | while read -r VMID; do
        INFO=$(ssh root@$NODE \
            "qm config $VMID 2>/dev/null | grep -E '^(name:|pool:)' | awk -F': ' '{print \$2}'")
        NAME=$(echo "$INFO" | sed -n '1p')
        POOL=$(echo "$INFO" | sed -n '2p')
        [[ -z "$POOL" ]] && POOL="none"
        echo "$VMID: $NAME (Pool: $POOL)"
    done)

    # Prompt user to select VMs to delete
    if [[ -z "$VM_LIST" ]]; then
        echo "No VMs or LXCs found on $NODE. Skipping..."
        continue
    fi

    # Format for whiptail menu
    MENU_LIST=()
    while IFS= read -r LINE; do
        ID=$(echo "$LINE" | cut -d: -f1)
        LABEL=$(echo "$LINE" | cut -d: -f2-)
        MENU_LIST+=("$ID" "$LABEL")
    done <<< "$VM_LIST"

    CHOICES=$(whiptail --title "Delete from $NODE" \
        --checklist "Select VMs or LXCs to DELETE on $NODE:" 20 80 10 \
        "${MENU_LIST[@]}" 3>&1 1>&2 2>&3)

    EXIT_STATUS=$?
    if [[ $EXIT_STATUS -ne 0 ]]; then
        echo "No selection made for $NODE. Skipping..."
        continue
    fi

    # Delete selected VMs
    for ID in $CHOICES; do
        CLEAN_ID=$(echo $ID | tr -d '"')
        echo "Deleting $CLEAN_ID on $NODE..."
        ssh root@$NODE "qm shutdown $CLEAN_ID --timeout 10 >/dev/null 2>&1; qm destroy $CLEAN_ID -purge >/dev/null 2>&1" && \
        echo "$CLEAN_ID deleted successfully on $NODE." || \
        echo "Failed to delete $CLEAN_ID on $NODE."
    done

done

echo "All node cleanup checks complete."
