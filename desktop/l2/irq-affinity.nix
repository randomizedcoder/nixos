# IRQ Affinity Configuration for L2 WiFi Access Point
# Optimizes interrupt distribution across dedicated network cores

{ config, lib, pkgs, ... }:

let
  # Network core assignments (cache-aware, paired SMT siblings)
  networkCores = "0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19";  # Dedicated network processing cores

  # IRQ affinity script (distribute across paired SMT siblings)
  irqAffinityScript = pkgs.writeShellScript "irq-affinity" ''
    #!/bin/bash
    set -euo pipefail

    echo "Setting IRQ affinity for network optimization (cache-aware, paired SMT siblings)..."

    # List of network cores (paired SMT siblings)
    network_cores=(0 12 1 13 2 14 3 15 4 16 5 17 6 18 7 19)
    irq_index=0
    for irq in $(grep -E '(enp|wlp)' /proc/interrupts | awk '{print $1}' | sed 's/://'); do
      cpu=${network_cores[$((irq_index % ${#network_cores[@]}))]}
      if [[ -e "/proc/irq/$irq/smp_affinity_list" ]]; then
        echo "$cpu" > "/proc/irq/$irq/smp_affinity_list"
        echo "IRQ $irq -> CPU $cpu"
      else
        echo "Warning: IRQ $irq not found"
      fi
      irq_index=$((irq_index + 1))
    done

    echo "IRQ affinity configuration complete"
    echo "Current IRQ distribution:"
    cat /proc/interrupts | grep -E "(enp|wlp)" | head -20
  '';

in {
  # IRQ Affinity Service
  systemd.services.irq-affinity = {
    description = "Set IRQ affinity for network optimization";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "systemd-udev-settle.service" ];
    before = [ "hostapd.service" "kea-dhcp4-server.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${irqAffinityScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}

# end