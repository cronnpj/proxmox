#!/bin/bash

# Proxmox nodes to update
NODES=(10.0.0.20 10.0.0.21 10.0.0.22 10.0.0.23 10.0.0.24 10.0.0.25 10.0.0.26 10.0.0.27 10.0.0.28)

# Production LXCs (Ubuntu) to update by VMID
PROD_LXC_VMIDS=(113 137 289)

# Logs
SUMMARY_LOG="/root/proxmox-update-summary.log"
> "$SUMMARY_LOG"
echo "Proxmox Update Report - $(date)" > "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

NODE_LOG_DIR="/tmp/proxmox_node_update_logs"
LXC_LOG_DIR="/tmp/proxmox_lxc_update_logs"
mkdir -p "$NODE_LOG_DIR" "$LXC_LOG_DIR"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)

# Convert node name (proxmox24) -> IP (10.0.0.24)
node_to_ip() {
  local NODE_NAME="$1"
  if [[ "$NODE_NAME" =~ ^proxmox([0-9]+)$ ]]; then
    echo "10.0.0.${BASH_REMATCH[1]}"
  else
    # fallback: if node name isn't in that format, just return it as-is
    echo "$NODE_NAME"
  fi
}

# Find where a VMID lives (returns: "<node> <type>")
# type is typically "qemu" or "lxc"
find_vmid_location() {
  local VMID="$1"
  # Requires python3 (present on Proxmox) and pvesh (present on Proxmox nodes)
  pvesh get /cluster/resources --type vm --output-format json | \
    python3 - "$VMID" <<'PY'
import json, sys
vmid = sys.argv[1]
data = json.load(sys.stdin)
for r in data:
    if str(r.get("vmid")) == str(vmid):
        print(r.get("node",""), r.get("type",""))
        sys.exit(0)
sys.exit(1)
PY
}

# Update a Ubuntu/Debian LXC using pct exec on its hosting node
update_ubuntu_lxc() {
  local NODE_IP="$1"
  local VMID="$2"
  local LOGFILE="$3"

  # Must be running
  local STATUS
  STATUS=$(ssh "${ssh_opts[@]}" root@"$NODE_IP" "pct status $VMID 2>/dev/null | awk '{print \$2}'")
  if [[ "$STATUS" != "running" ]]; then
    echo "LXC $VMID on $NODE_IP: skipped (status: ${STATUS:-unknown})" >> "$LOGFILE"
    return 2
  fi

  echo "Updating LXC $VMID on $NODE_IP..." >> "$LOGFILE"
  ssh "${ssh_opts[@]}" root@"$NODE_IP" \
    "pct exec $VMID -- sh -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade && apt-get -y autoremove'" \
    >> "$LOGFILE" 2>&1
  local RC=$?

  if [[ $RC -eq 0 ]]; then
    echo "LXC $VMID: success" >> "$LOGFILE"
    local REBOOT
    REBOOT=$(ssh "${ssh_opts[@]}" root@"$NODE_IP" \
      "pct exec $VMID -- sh -lc '[ -f /var/run/reboot-required ] && echo reboot-required || echo no-reboot-required' 2>/dev/null")
    echo "LXC $VMID reboot status: $REBOOT" >> "$LOGFILE"
    return 0
  else
    echo "LXC $VMID: failed (rc=$RC)" >> "$LOGFILE"
    return 1
  fi
}

# ----------------------------
# 1) Update Proxmox nodes
# ----------------------------
for NODE in "${NODES[@]}"; do
  echo "Updating Proxmox node at $NODE..."
  NODE_LOG="$NODE_LOG_DIR/update_${NODE}.log"

  ssh "${ssh_opts[@]}" root@"$NODE" "apt update && apt -y full-upgrade" > "$NODE_LOG" 2>&1
  if [[ $? -eq 0 ]]; then
    echo "$NODE: Success" >> "$SUMMARY_LOG"
  else
    echo "$NODE: Failed (see $NODE_LOG)" >> "$SUMMARY_LOG"
    continue
  fi

  KERNEL_INFO=$(ssh "${ssh_opts[@]}" root@"$NODE" "uname -r" 2>/dev/null)
  UPTIME_INFO=$(ssh "${ssh_opts[@]}" root@"$NODE" "uptime -p" 2>/dev/null)
  echo "Kernel: $KERNEL_INFO, Uptime: $UPTIME_INFO" >> "$SUMMARY_LOG"

  REBOOT_NEEDED=$(ssh "${ssh_opts[@]}" root@"$NODE" "[ -f /var/run/reboot-required ] && echo reboot-required || echo no-reboot-required" 2>/dev/null)
  echo "$NODE reboot status: $REBOOT_NEEDED" >> "$SUMMARY_LOG"
done

# ----------------------------
# 2) Update selected production Ubuntu LXCs by VMID
# ----------------------------
echo "" >> "$SUMMARY_LOG"
echo "Production LXC Updates (Ubuntu):" >> "$SUMMARY_LOG"
echo "----------------------------------" >> "$SUMMARY_LOG"

for VMID in "${PROD_LXC_VMIDS[@]}"; do
  LOC=$(find_vmid_location "$VMID")
  if [[ $? -ne 0 || -z "$LOC" ]]; then
    echo "VMID $VMID: not found in cluster resources" >> "$SUMMARY_LOG"
    continue
  fi

  NODE_NAME=$(echo "$LOC" | awk '{print $1}')
  VM_TYPE=$(echo "$LOC" | awk '{print $2}')

  if [[ "$VM_TYPE" != "lxc" ]]; then
    echo "VMID $VMID: skipped (type=$VM_TYPE, expected lxc)" >> "$SUMMARY_LOG"
    continue
  fi

  NODE_IP=$(node_to_ip "$NODE_NAME")
  LXC_LOG="$LXC_LOG_DIR/lxc_${NODE_NAME}_${VMID}.log"
  : > "$LXC_LOG"

  update_ubuntu_lxc "$NODE_IP" "$VMID" "$LXC_LOG"
  RC=$?

  if [[ $RC -eq 0 ]]; then
    echo "VMID $VMID on $NODE_NAME ($NODE_IP): success (log: $LXC_LOG)" >> "$SUMMARY_LOG"
  elif [[ $RC -eq 2 ]]; then
    echo "VMID $VMID on $NODE_NAME ($NODE_IP): skipped (not running) (log: $LXC_LOG)" >> "$SUMMARY_LOG"
  else
    echo "VMID $VMID on $NODE_NAME ($NODE_IP): failed (log: $LXC_LOG)" >> "$SUMMARY_LOG"
  fi
done

# ----------------------------
# Summary display
# ----------------------------
echo ""
echo "===== Summary ====="
cat "$SUMMARY_LOG"
echo ""
echo "Update process completed. Summary log saved to $SUMMARY_LOG"
