#!/bin/bash

# List of Proxmox host IPs
# HOSTS=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
HOSTS=(136.204.36.19)

# Check for whiptail
if ! command -v whiptail &> /dev/null; then
    echo "whiptail is required. Install it with: apt install whiptail"
    exit 1
fi

for HOST in "${HOSTS[@]}"; do
    echo "Checking $HOST for VMs/LXCs..."

    TMPFILE=$(mktemp)
    CHOICES=()

    # Fetch remote VMs with descriptions
    for VMID in $(ssh root@$HOST "qm list | awk 'NR>1 {print \$1}'"); do
        NAME=$(ssh root@$HOST "qm config $VMID | awk -F': ' '/^name/ {print \$2}'")
        DESC=$(ssh root@$HOST "qm config $VMID | awk -F': ' '/^description/ {print \$2}'")
        DISPLAY="${NAME:-$VMID}"
        [[ -n "$DESC" ]] && DISPLAY="$DISPLAY - $DESC"
        CHOICES+=("$VMID" "$DISPLAY" "OFF")
    done

    # Fetch remote LXCs with descriptions
    for CTID in $(ssh root@$HOST "pct list | awk 'NR>1 {print \$1}'"); do
        NAME=$(ssh root@$HOST "pct config $CTID | awk -F': ' '/^hostname/ {print \$2}'")
        DESC=$(ssh root@$HOST "pct config $CTID | awk -F': ' '/^description/ {print \$2}'")
        DISPLAY="${NAME:-$CTID}"
        [[ -n "$DESC" ]] && DISPLAY="$DISPLAY - $DESC"
        CHOICES+=("$CTID" "$DISPLAY" "OFF")
    done

    # Skip if no items
    if [[ ${#CHOICES[@]} -eq 0 ]]; then
        echo "No VMs or LXCs found on $HOST."
        continue
    fi

    # Show selection menu
    whiptail --title "Delete from $HOST" --checklist \
    "Select VMs or LXCs to DELETE on $HOST:" 25 78 15 \
    "${CHOICES[@]}" 2> "$TMPFILE"

    if [[ $? -eq 0 ]]; then
        SELECTED=$(cat "$TMPFILE")
        echo "Selected for deletion on $HOST: $SELECTED"
        for ID in $SELECTED; do
            CLEAN_ID=$(echo "$ID" | tr -d '"')
            if ssh root@$HOST "qm status $CLEAN_ID &>/dev/null"; then
                echo "Deleting VM $CLEAN_ID on $HOST..."
                ssh root@$HOST "qm destroy $CLEAN_ID"
            elif ssh root@$HOST "pct status $CLEAN_ID &>/dev/null"; then
                echo "Deleting LXC $CLEAN_ID on $HOST..."
                ssh root@$HOST "pct destroy $CLEAN_ID"
            else
                echo "❌ Could not find $CLEAN_ID on $HOST"
            fi
        done
    else
        echo "No selection made for $HOST. Moving on..."
    fi

    rm -f "$TMPFILE"
done

echo "Bulk deletion process complete."
