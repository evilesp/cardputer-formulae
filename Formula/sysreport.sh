#!/bin/bash
# sysreport: a report of this system: memory, disk, network, the biggest folders, and what is wrong. sysreport [-s FILE] saves it.
set -u
out=""
usage() { echo "usage: sysreport [-s FILE]"; }
while getopts "s:h" o; do
  case "$o" in
    s) out="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
warnings=()
section() { printf '\n== %s ==\n' "$1"; }
report() {
  echo "report of $(hostname) at $(date '+%Y-%m-%d %H:%M')"
  section system
  uname -sr
  uptime
  section memory
  free -h 2>/dev/null || free
  section disk
  df -h / 2>/dev/null || df
  use=$(df / | tail -n 1 | awk '{print $5}' | tr -d '%')
  if [[ -n "$use" && "$use" -gt 90 ]]; then warnings+=("the disk is ${use}% full"); fi
  section network
  ip addr 2>/dev/null | grep -E 'inet |state' | head -n 6
  if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then warnings+=("no answer from the internet"); fi
  section "biggest folders in $HOME"
  du -s "$HOME"/* 2>/dev/null | sort -rn | head -n 5
  section summary
  if [ ${#warnings[@]} -eq 0 ]; then
    echo "all is well"
  else
    for w in "${warnings[@]}"; do echo "WARNING: $w"; done
  fi
}
if [ -n "$out" ]; then
  report > "$out"
  echo "saved to $out"
else
  report
fi
