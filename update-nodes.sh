#!/bin/bash

# Node IPs
NODES=(136.204.36.19 136.204.36.20 136.204.36.21 136.204.36.22 136.204.36.23 136.204.36.24 136.204.36.25 136.204.36.26 136.204.36.27 136.204.36.28)
# For testing script NODES=(136.204.36.19)

# Log and summary file
SUMMARY_LOG="/root/proxmox-update-summary.log"
> "$SUMMARY_LOG"
echo "Proxmox Update Report - $(date)" > "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

# Update loop
for NODE in "${NODES[@]}"; do
    echo "Updating Proxmox node at $NODE..."
    ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE "apt update && apt -y full-upgrade" > /tmp/update_$NODE.log 2>&1

    if [[ $? -eq 0 ]]; then
        echo "✅ $NODE updated successfully"
        echo "$NODE: ✅ Success" >> "$SUMMARY_LOG"
    else
        echo "❌ $NODE update failed"
        echo "$NODE: ❌ Failed (see /tmp/update_$NODE.log)" >> "$SUMMARY_LOG"
        continue
    fi

    # Show kernel and uptime live
    KERNEL_INFO=$(ssh root@$NODE "uname -r")
    UPTIME_INFO=$(ssh root@$NODE "uptime -p")
    echo "   Kernel: $KERNEL_INFO"
    echo "   Uptime: $UPTIME_INFO"
    echo "Kernel: $KERNEL_INFO, Uptime: $UPTIME_INFO" >> "$SUMMARY_LOG"

    # Show reboot-needed status live
    REBOOT_NEEDED=$(ssh root@$NODE "[ -f /var/run/reboot-required ] && echo '🔁 Reboot Required' || echo '✅ No Reboot Needed'")
    echo "   $REBOOT_NEEDED"
    echo "$REBOOT_NEEDED" >> "$SUMMARY_LOG"
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

# echo ""
# read -p "Do you want to update the LXC containers on this host? (y/n): " lxc_choice
# if [[ "$lxc_choice" =~ ^[Yy]$ ]]; then
#    echo "Running LXC container update script..."
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/update-lxcs.sh)"
# else
#    echo "Skipping LXC container updates."
# fi

echo ""
echo "===== Summary ====="
grep -E '^[0-9]' "$SUMMARY_LOG"

echo "Update process completed. Summary log saved to $SUMMARY_LOG"
