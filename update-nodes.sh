#!/bin/bash

# Proxmox node + production LXC updater
# - Updates Proxmox nodes via SSH (apt full-upgrade)
# - Updates selected production Ubuntu LXCs via SSH by IP (apt dist-upgrade)

set -u

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root."
  exit 1
fi

# Proxmox node IPs (management network)
NODES=(10.0.0.20 10.0.0.21 10.0.0.22 10.0.0.23 10.0.0.24 10.0.0.25 10.0.0.26 10.0.0.27 10.0.0.28)
# For testing: NODES=(10.0.0.24)

# Production Ubuntu LXC IPs (must be reachable via SSH from the machine running this script)
PROD_LXC_IPS=(
  #10.0.0.5 # Proxmox-backup-server
  10.0.0.6 #Production-Docker-v2
  #10.0.0.7 #Production-Docker
  10.0.0.8 #influxdb-template
)

# SSH options
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

# Log and summary file
SUMMARY_LOG="/root/proxmox-update-summary.log"
: > "$SUMMARY_LOG"
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

  KERNEL_INFO=$(ssh "${SSH_OPTS[@]}" root@"$NODE" "uname -r" 2>/dev/null || echo "unknown")
  UPTIME_INFO=$(ssh "${SSH_OPTS[@]}" root@"$NODE" "uptime -p" 2>/dev/null || echo "unknown")
  echo "   Kernel: $KERNEL_INFO"
  echo "   Uptime: $UPTIME_INFO"
  echo "$NODE kernel: $KERNEL_INFO, uptime: $UPTIME_INFO" >> "$SUMMARY_LOG"

  REBOOT_NEEDED=$(ssh "${SSH_OPTS[@]}" root@"$NODE" "[ -f /var/run/reboot-required ] && echo '🔁 Reboot Required' || echo '✅ No Reboot Needed'" 2>/dev/null || echo "unknown")
  echo "   $REBOOT_NEEDED"
  echo "$NODE: $REBOOT_NEEDED" >> "$SUMMARY_LOG"
done

# ----------------------------
# 2) Update production Ubuntu LXCs by IP
# ----------------------------
echo "" >> "$SUMMARY_LOG"
echo "Production LXC Updates (Ubuntu via SSH):" >> "$SUMMARY_LOG"
echo "----------------------------------------" >> "$SUMMARY_LOG"

if [[ ${#PROD_LXC_IPS[@]} -eq 0 ]]; then
  echo "(none configured)" >> "$SUMMARY_LOG"
else
  for CIP in "${PROD_LXC_IPS[@]}"; do
    echo "Updating production LXC at $CIP..."
    LXC_LOG="$LXC_LOG_DIR/update_lxc_${CIP}.log"

    ssh "${SSH_OPTS[@]}" root@"$CIP" \
      "apt update && DEBIAN_FRONTEND=noninteractive apt -y dist-upgrade && apt -y autoremove" \
      > "$LXC_LOG" 2>&1

    if [[ $? -eq 0 ]]; then
      echo "✅ $CIP updated successfully"
      echo "$CIP: ✅ Success (LXC)" >> "$SUMMARY_LOG"

      LXC_REBOOT=$(ssh "${SSH_OPTS[@]}" root@"$CIP" \
        "[ -f /var/run/reboot-required ] && echo '🔁 Reboot Required' || echo '✅ No Reboot Needed'" \
        2>/dev/null || echo "unknown")

      echo "   $LXC_REBOOT"
      echo "$CIP: $LXC_REBOOT" >> "$SUMMARY_LOG"
    else
      echo "❌ $CIP update failed"
      echo "$CIP: ❌ Failed (see $LXC_LOG)" >> "$SUMMARY_LOG"
    fi
  done
fi

# ----------------------------
# 3) Append detailed logs to summary file
# ----------------------------
echo "" >> "$SUMMARY_LOG"
echo "Detailed Node Reports:" >> "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

for NODE in "${NODES[@]}"; do
  NODE_LOG="$NODE_LOG_DIR/update_${NODE}.log"
  echo "----- $NODE -----" >> "$SUMMARY_LOG"
  [[ -f "$NODE_LOG" ]] && cat "$NODE_LOG" >> "$SUMMARY_LOG" || echo "(no log found)" >> "$SUMMARY_LOG"
  echo "" >> "$SUMMARY_LOG"
done

echo "" >> "$SUMMARY_LOG"
echo "Detailed LXC Reports:" >> "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

if [[ ${#PROD_LXC_IPS[@]} -gt 0 ]]; then
  for CIP in "${PROD_LXC_IPS[@]}"; do
    LXC_LOG="$LXC_LOG_DIR/update_lxc_${CIP}.log"
    echo "----- LXC $CIP -----" >> "$SUMMARY_LOG"
    [[ -f "$LXC_LOG" ]] && cat "$LXC_LOG" >> "$SUMMARY_LOG" || echo "(no log found)" >> "$SUMMARY_LOG"
    echo "" >> "$SUMMARY_LOG"
  done
else
  echo "(none configured)" >> "$SUMMARY_LOG"
fi

# ----------------------------
# 4) Print summary
# ----------------------------
echo ""
echo "===== Summary ====="
grep -E '✅|❌|Reboot Required|No Reboot Needed' "$SUMMARY_LOG" || true

echo ""
echo "Update process completed. Summary log saved to $SUMMARY_LOG"
