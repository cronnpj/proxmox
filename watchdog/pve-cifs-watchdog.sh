#!/bin/bash
set -euo pipefail

STORAGE="${STORAGE:-ExternalStorage}"
MOUNTPOINT="${MOUNTPOINT:-/mnt/pve/ExternalStorage}"
LOGTAG="pve-cifs-watchdog"

log() { logger -t "$LOGTAG" "$*"; }

# If Proxmox thinks it's active, we're done.
status="$(pvesm status 2>/dev/null | awk '$1=="'"$STORAGE"'" {print $3}' || true)"
if [[ "$status" == "active" ]]; then
  exit 0
fi

log "Storage '$STORAGE' is '$status' (expected active). Attempting recovery."

# Try a clean activate first
if pvesm activate "$STORAGE" >/dev/null 2>&1; then
  log "pvesm activate succeeded."
  exit 0
fi

log "pvesm activate failed. Forcing lazy unmount + daemon restart."

# Stop services that poke mountpoints
systemctl stop pvestatd pvedaemon >/dev/null 2>&1 || true

# Kill anything holding the mount (best-effort)
fuser -km "$MOUNTPOINT" >/dev/null 2>&1 || true

# Detach stale CIFS mounts
umount -l "$MOUNTPOINT" >/dev/null 2>&1 || true

# Bring services back
systemctl start pvedaemon pvestatd >/dev/null 2>&1 || true

# Try activation again
if pvesm activate "$STORAGE" >/dev/null 2>&1; then
  log "Recovery successful: storage activated."
  exit 0
fi

log "Recovery failed: storage still inactive."
exit 1
