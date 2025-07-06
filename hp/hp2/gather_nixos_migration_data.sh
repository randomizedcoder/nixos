#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <output-file>"
  echo "Example: $0 /tmp/nixos_migration.log"
  exit 1
fi

OUTPUT_FILE=$1

# Commands that do NOT require sudo
NORMAL_COMMANDS=(
  "uname -a"
  "cat /etc/lsb-release"
  "ifconfig -a"
  "ip addr"
  "ip -6 addr"
  "ip route"
  "ip -6 route"
)

# Commands that require sudo
SUDO_COMMANDS=(
  # Network
  "cat /etc/netplan/*.yaml"
  "iptables-save"
  "for iface in \$(ls /sys/class/net); do ethtool \$iface >/dev/null 2>&1 && echo \"--- ethtool \$iface ---\" && ethtool \$iface; done"

  # Disk
  "lsblk -f"
  "lsblk -d -o NAME,MODEL,ROTA,SIZE,TYPE,TRAN"
  "mount"
  "df -h"
  "cat /etc/fstab"

  # WireGuard
  "wg show"
  "systemctl status wg-quick@* || true"
  "cat /etc/wireguard/*.conf 2>/dev/null || echo 'No WireGuard config files found'"

  # DHCP
  "ps aux | grep [d]hcpd"
  "cat /etc/dhcp/dhcpd.conf 2>/dev/null || echo 'No dhcpd.conf found'"
  "systemctl status isc-dhcp-server 2>/dev/null || systemctl status dhcpd 2>/dev/null || echo 'DHCP service not found'"

  # Hardware
  "lspci -nn"
  "which hwloc-ls >/dev/null && hwloc-ls || which lstopo-no-graphics >/dev/null && lstopo-no-graphics || echo 'hwloc-ls not available'"
)

{
  echo "=== Host: $(hostname) ==="
  echo
  echo "=== NON-SUDO COMMANDS ==="
  echo

  for CMD in "${NORMAL_COMMANDS[@]}"; do
    echo ">>> $CMD"
    bash -c "$CMD" || echo "Command failed: $CMD"
    echo
  done

  echo "=== SUDO COMMANDS ==="
  echo

  for CMD in "${SUDO_COMMANDS[@]}"; do
    echo ">>> sudo $CMD"
    sudo bash -c "$CMD" || echo "Command failed: $CMD"
    echo
  done
} > "$OUTPUT_FILE"

echo "✅ Local info gathered to: $OUTPUT_FILE"
