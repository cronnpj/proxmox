#!/usr/bin/env bash
#
#  LXC / VM delete helper for Proxmox VE
#  Copyright (c) 2021‑2025 community‑scripts
#  Author: MickLesk (CanbiZ)  |  Mod: PatCronn‑mix
#  License: MIT

set -eEuo pipefail

#####  ── helpers ────────────────────────────────────────────────────────────
header_info() {
  clear
  cat <<"EOF"
    ____                                          __   _  ________   ____       __     __     
   / __ \_________  _  ______ ___  ____  _  __   / /  | |/ / ____/  / __ \___  / /__  / /____ 
  / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/  / /   |   / / /      / / / / _ \/ / _ \/ __/ _ \
 / ____/ /  / /_/ />  </ / / / / / /_/ />  <   / /___/   / /___   / /_/ /  __/ /  __/ /_/  __/
/_/   /_/   \____/_/|_/_/ /_/ /_/\____/_/|_|  /_____/_/|_\____/  /_____/\___/_/\___/\__/\___/ 
EOF
}

spinner() {
  local pid=$1 delay=0.1 spin='|/-\'
  while ps -p "$pid" &>/dev/null; do
    printf ' [%c]  ' "$spin"
    spin=${spin#?}${spin%"${spin#?}"}; sleep "$delay"; printf '\r'
  done; printf '    \r'
}

YW=$'\033[33m'; BL=$'\033[36m'; RD=$'\033[01;31m'; GN=$'\033[1;92m'; CL=$'\033[m'
FORMAT="%-3s %-10s %-15s %-10s"   # Type  ID  Name  Status

#####  ── intro / safety ─────────────────────────────────────────────────────
header_info
echo "Loading…"

whiptail --backtitle "Proxmox VE Helper Scripts" \
         --title     "Proxmox VE Guest Deletion" \
         --yesno     "This will delete **containers and VMs** on host $(hostname).\nProceed?" 12 70 \
  || exit 0

#####  ── build guest list ───────────────────────────────────────────────────
declare -A GTYPE   # map[VMID]=CT|VM

guests_raw="$(
  { pct list | tail -n +2 | awk '{printf "CT %s %s %s\n",$1,$2,$3}'; } ;\
  { qm  list | tail -n +2 | awk '{printf "VM %s %s %s\n",$1,$2,$3}'; }
)"

if [[ -z "$guests_raw" ]]; then
  whiptail --title "Delete Guests" --msgbox "No VMs or containers found on this node!" 10 60
  exit 1
fi

menu_items=()
while read -r gtype gid gname gstate; do
  GTYPE["$gid"]=$gtype
  line=$(printf "$FORMAT" "$gtype" "$gid" "$gname" "$gstate")
  menu_items+=("$gid" "$line" "OFF")
done <<<"$guests_raw"

CHOICES=$(whiptail --title "Select Guests to Delete" \
                   --checklist "Space‑select, <OK> to continue" 25 70 15 \
                   "${menu_items[@]}" 3>&2 2>&1 1>&3) || exit 0

[[ -z "$CHOICES" ]] && { whiptail --msgbox "Nothing selected." 8 40; exit 0; }

read -rp "Delete guests manually or automatically? (m/a) [m]: " DELETE_MODE
DELETE_MODE=${DELETE_MODE:-m}

#####  ── deletion loop ──────────────────────────────────────────────────────
for id in $(tr -d '"' <<<"$CHOICES"); do
  typ=${GTYPE[$id]}
  if [[ "$typ" == "CT" ]]; then
    state=$(pct status "$id" | awk '{print $2}')
    [[ "$state" == "running" ]] && { echo -e "${BL}[Info]${GN} Stopping CT $id…${CL}"; pct stop "$id"; }
    delete_cmd=("pct" "destroy" "$id" "-f")
  else
    state=$(qm status "$id" | awk '{print $2}')
    [[ "$state" == "running" ]] && { echo -e "${BL}[Info]${GN} Stopping VM $id…${CL}"; qm stop "$id"; }
    delete_cmd=("qm" "destroy" "$id" "--purge")
  fi

  if [[ "$DELETE_MODE" == "a" ]]; then
    echo -e "${BL}[Info]${GN} Deleting $typ $id…${CL}"
    "${delete_cmd[@]}" & spinner $!
  else
    read -rp "Delete $typ $id? (y/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo -e "${BL}[Info]${RD} Skipped $typ $id${CL}"; continue; }
    echo -e "${BL}[Info]${GN} Deleting $typ $id…${CL}"
    "${delete_cmd[@]}" & spinner $!
  fi
done

#####  ── done ───────────────────────────────────────────────────────────────
header_info
echo -e "${GN}Deletion process completed.${CL}\n"
