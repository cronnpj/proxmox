#!/bin/bash

# Node IPs
NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)

# Log and summary file
SUMMARY_LOG="/root/proxmox-update-summary.log"
> "$SUMMARY_LOG"
echo "Proxmox Update Report - $(date)" > "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

# Update loop
for NODE in "${NODES[@]}"; do
    echo "Updating Proxmox node at $NODE..."
    echo -n "$NODE: " >> "$SUMMARY_LOG"
    ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE "apt update && apt -y full-upgrade" > /tmp/update_$NODE.log 2>&1
    if [[ $? -eq 0 ]]; then
        echo "✅ Success" >> "$SUMMARY_LOG"
    else
        echo "❌ Failed (see /tmp/update_$NODE.log)" >> "$SUMMARY_LOG"
    fi
done

echo "" >> "$SUMMARY_LOG"
echo "Detailed Report:" >> "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

# Append detailed info
for NODE in "${NODES[@]}"; do
    echo "----- $NODE -----" >> "$SUMMARY_LOG"
    cat /tmp/update_$NODE.log >> "$SUMMARY_LOG"
    echo "" >> "$SUMMARY_LOG"
done

# OPTIONAL: Send the summary via email (requires mail or msmtp configured)
# mail -s "Proxmox Update Report - $(date '+%Y-%m-%d')" your.email@example.com < "$SUMMARY_LOG"

echo "Update process completed. Summary log saved to $SUMMARY_LOG"