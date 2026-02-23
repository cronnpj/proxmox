#!/bin/bash
set -euo pipefail

STORAGE="${STORAGE:-ExternalStorage}"
MOUNTPOINT="${MOUNTPOINT:-/mnt/pve/ExternalStorage}"

# Where to download from (raw GitHub URLs)
BASE_URL="${BASE_URL:?Set BASE_URL to your raw GitHub directory URL}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -fsSL "$BASE_URL/pve-cifs-watchdog.sh" -o "$tmpdir/pve-cifs-watchdog.sh"
curl -fsSL "$BASE_URL/pve-cifs-watchdog.service" -o "$tmpdir/pve-cifs-watchdog.service"
curl -fsSL "$BASE_URL/pve-cifs-watchdog.timer" -o "$tmpdir/pve-cifs-watchdog.timer"

# Inject storage/mountpoint into script if you want it configurable
install -m 0755 "$tmpdir/pve-cifs-watchdog.sh" /usr/local/sbin/pve-cifs-watchdog.sh
install -m 0644 "$tmpdir/pve-cifs-watchdog.service" /etc/systemd/system/pve-cifs-watchdog.service
install -m 0644 "$tmpdir/pve-cifs-watchdog.timer" /etc/systemd/system/pve-cifs-watchdog.timer

systemctl daemon-reload
systemctl enable --now pve-cifs-watchdog.timer

echo "Installed and enabled pve-cifs-watchdog.timer"
systemctl --no-pager status pve-cifs-watchdog.timer || true
