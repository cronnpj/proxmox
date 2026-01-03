#!/bin/bash

# ----------------------------
# Proxmox node + production LXC updater
# - Updates Proxmox nodes via SSH (apt full-upgrade)
# - Updates selected production Ubuntu LXCs via SSH by IP (apt dist-upgrade)
# ----------------------------

set -u

# Proxmox node IPs (management network)
NODES=(10.0.0.20 10.0.0.21 10.0.0.22 10.0.0.23 10.0.0.24 10.0.0.25 10.0.0.26 10.0.0.27 10.0.0.28)
# For testing: NODES=(10.0.0.24)

# Production Ubuntu LXC IPs (must be reachable via SSH from the machine running this script)
# Add your containers here (examples shown). You mentioned "10.0.0.5"—put it in the list.
PROD_LXC_IPS=(
  10.0.0.5
  # 10.0.0.6
  # 10.0.0.7
)

# SSH options
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

# Log and summary file
SUMMARY_LOG="/root/proxmox-update-summary.log"
> "$SUMMARY_LOG"
{
  echo "Proxmox + Production LXC Update Report - $(date)"
  echo "----------------------------------------------"
} >> "$SUMMARY_LOG"

# Per-run log directories
NODE_LOG_DIR="/tmp/proxmox_node_update_logs"
LXC_LOG_DIR="/tmp/proxmox_lxc_update_logs"
mkdir -p "$NODE_LOG_DIR" "$LXC_LOG_DIR"

# ----------------------------
# 1) Update Proxmox nodes
# ----------------------------
for NODE in "${NODES[@]}"; do
  echo "Updating Proxmox node at $NODE..."
  NODE_LOG="$NODE_LOG_DIR/update_${NODE}.log"

  ssh "${SSH_OPTS[@]}" root@"$NODE" "apt update && apt -y full-upgrade" > "$NODE_LOG" 2>&1
  if [[ $? -eq 0 ]]; then
    echo "✅ $NODE updated successfully"
    echo "$NODE: ✅ Success (Proxmox node)" >> "$SUMMARY_LOG"
  else
    echo "❌ $NODE update failed"
    echo "$NODE: ❌ Failed (see $NODE_LOG)" >> "$SUMMARY_LOG"
    continue
  fi

  # Show kernel and uptime
  KERNEL_INFO=$(ssh "${SSH_OPTS[@]}" root@"$NODE" "uname -r" 2>/dev/null || echo "unknown")
  UPTIME_INFO=$(ssh "${SSH_OPTS[@]}" root@"$NODE" "uptime -p" 2>/dev/null || echo "unknown")
  echo "   Kernel: $KERNEL_INFO"
  echo "   Uptime: $UPTIME_INFO"
  echo "Kernel: $KERNEL_INFO, Uptime: $UPTIME_INFO" >> "$SUMMARY_LOG"

  # Reboot-needed flag (Debian/Proxmox style)
  REBOOT_NEEDED=$(ssh "${SSH_OPTS[@]}" root@"$NODE" "[ -f /var/run/reboot-required ] && echo '🔁 Reboot Required' || echo '✅ No Reboot Needed'" 2>/dev/null || echo "unknown")
  echo "   $REBOOT_NEEDED"
  echo "$REBOOT_NEEDED" >> "$SUMMA_
