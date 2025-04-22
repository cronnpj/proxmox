
#!/bin/bash

# Array of Proxmox node IPs
#NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
NODES=(136.204.36.19)

# Loop through each node
for NODE in "${NODES[@]}"; do
    echo "Checking VMs and LXCs on $NODE..."

    # Get list of QEMU VMs (VMID, Name, Pool)
    QEMU_LIST=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE "qm list 2> >(grep -v 'invalid group member' >&2) | awk 'NR>1 {vmid=\$1; name=\$2; pool=\$NF; print vmid":"name":"pool}'")
    
    # Get list of LXCs (VMID, Status, Name)
    #LXC_LIST=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE "pct list | awk 'NR>1 {vmid=\$1; status=\$2; name=\$NF; print vmid":"name":""\$2""}'")
    LXC_LIST=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE "pct list | awk 'NR>1 {vmid=\$1; status=\$2; name=\$NF; print vmid\":\"name\":\"\"status\"}'")
    
    # Combine both lists
    COMBINED_LIST=$(echo -e "$QEMU_LIST
$LXC_LIST" | grep -E '^[0-9]+:')

    if [[ -z "$COMBINED_LIST" ]]; then
        echo "No VMs or LXCs found on $NODE. Skipping..."
        continue
    fi

    # Build whiptail options string
    OPTIONS=()
    while IFS=: read -r ID NAME META; do
        ENTRY="$ID: $NAME"
        [[ -n "$META" ]] && ENTRY="$ENTRY ($META)"
        OPTIONS+=("$ID" "$ENTRY" "off")
    done <<< "$COMBINED_LIST"

    CHOICE=$(whiptail --title "Delete from $NODE" --checklist "Select VMs or LXCs to DELETE on $NODE:" 20 80 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$CHOICE" ]]; then
        echo "No selection made for $NODE. Skipping..."
        continue
    fi

    # Clean choice into array
    IFS=' ' read -r -a TO_DELETE <<< "$CHOICE"

    for ID in "${TO_DELETE[@]}"; do
        CLEAN_ID=$(echo "$ID" | tr -d '"')
        echo "Attempting to delete $CLEAN_ID on $NODE..."

        # Check if LXC or QEMU
        if ssh root@$NODE pct status "$CLEAN_ID" &>/dev/null; then
            ssh root@$NODE "pct shutdown $CLEAN_ID --force && pct destroy $CLEAN_ID"
        elif ssh root@$NODE qm status "$CLEAN_ID" &>/dev/null; then
            ssh root@$NODE "qm shutdown $CLEAN_ID --forceStop 1 && qm destroy $CLEAN_ID"
        else
            echo "Unable to determine type for $CLEAN_ID on $NODE."
        fi
    done

    echo "Node $NODE cleanup done."
    echo "--------------------------"

done

echo "All node cleanup checks complete."
