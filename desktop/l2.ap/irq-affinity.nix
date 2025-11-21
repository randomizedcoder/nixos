# IRQ Affinity Configuration for L2 WiFi Access Point
# Optimizes interrupt distribution across dedicated network cores

{ config, lib, pkgs, ... }:

let
  # Network core assignments (cache-aware, paired SMT siblings)
  # Ethernet IRQs: cores 0,12,1,13,2,14,3,15 (first 4 L cores)
  # WiFi IRQs: cores 4,5,6,7 (dedicated L cores for default queues)
  # Userland: cores 8,20,9,21,10,22,11,23 (remaining 4 L cores)
  ethernetCores = "0,12,1,13,2,14,3,15";  # Ethernet IRQ cores
  wifiCores = "4,5,6,7";                  # WiFi default queue cores (L cores)
  userlandCores = "8,20,9,21,10,22,11,23"; # Userland cores

  # IRQ affinity script (optimize WiFi default queues across dedicated L cores)
  irqAffinityScript = pkgs.writeShellScript "irq-affinity" ''
    #!/bin/bash
    set -euo pipefail

    echo "Setting IRQ affinity for network optimization..."

    # Ethernet cores (first 4 L cores)
    ethernet_cores="0 12 1 13 2 14 3 15"
    # WiFi default queue cores (L cores 4,5,6,7)
    wifi_default_cores="4 5 6 7"

    # Distribute Ethernet IRQs across ethernet cores
    echo "Distributing Ethernet IRQs across cores: ${ethernetCores}"
    irq_index=0

    # Get Ethernet interface PCI devices dynamically
    for interface in $(${pkgs.iproute2}/bin/ip link show | ${pkgs.gnugrep}/bin/grep -E "enp|eth" | ${pkgs.gawk}/bin/awk -F: '{print $2}' | ${pkgs.gnused}/bin/sed 's/ //g'); do
      # Get PCI device for this interface using /sys/class/net/
      pci_device_path="/sys/class/net/$interface/device"
      if [ -L "$pci_device_path" ]; then
        pci_device=$(basename $(readlink "$pci_device_path"))
        if [ -n "$pci_device" ]; then
          echo "Processing Ethernet interface $interface (PCI: $pci_device)"
          # Get IRQs for this PCI device
          for irq in $(cat /proc/interrupts | ${pkgs.gnugrep}/bin/grep "$pci_device" | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.gnused}/bin/sed 's/://'); do
            cpu_index=$((irq_index % 8))
            # Convert index to actual CPU number
            case $cpu_index in
              0) cpu=0 ;;
              1) cpu=12 ;;
              2) cpu=1 ;;
              3) cpu=13 ;;
              4) cpu=2 ;;
              5) cpu=14 ;;
              6) cpu=3 ;;
              7) cpu=15 ;;
            esac
            if [[ -e "/proc/irq/$irq/smp_affinity_list" ]]; then
              echo "$cpu" > "/proc/irq/$irq/smp_affinity_list"
              echo "Ethernet IRQ $irq ($interface) -> CPU $cpu"
            else
              echo "Warning: Ethernet IRQ $irq not found"
            fi
            irq_index=$((irq_index + 1))
          done
        else
          echo "Warning: Could not determine PCI device for interface $interface"
        fi
      else
        echo "Warning: Could not find device path for interface $interface"
      fi
    done

    # Optimize WiFi default queues across dedicated L cores
    echo "Optimizing WiFi default queues across cores: ${wifiCores}"

    # Get all WiFi default queue IRQs by PCI device
    wifi_default_irqs=$(cat /proc/interrupts | ${pkgs.gnugrep}/bin/grep "iwlwifi:default_queue" | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.gnused}/bin/sed 's/://')

    if [ -n "$wifi_default_irqs" ]; then
      wifi_count=0
      for irq in $wifi_default_irqs; do
        # Assign each WiFi default queue to a dedicated L core (4,5,6,7)
        case $wifi_count in
          0) default_core=4 ;;  # First WiFi device -> L core 4
          1) default_core=5 ;;  # Second WiFi device -> L core 5
          2) default_core=6 ;;  # Third WiFi device -> L core 6
          3) default_core=7 ;;  # Fourth WiFi device -> L core 7
        esac

        if [[ -e "/proc/irq/$irq/smp_affinity_list" ]]; then
          echo "$default_core" > "/proc/irq/$irq/smp_affinity_list"
          echo "WiFi default queue IRQ $irq -> CPU $default_core"
        else
          echo "Warning: WiFi default queue IRQ $irq not found"
        fi

        # Set all other queues for this WiFi device to same core as default queue
        pci_device=$(${pkgs.gnugrep}/bin/grep "^ *$irq:" /proc/interrupts | ${pkgs.gnugrep}/bin/grep -o "0000:[0-9a-f:]*")
        if [ -n "$pci_device" ]; then
          for queue_irq in $(cat /proc/interrupts | ${pkgs.gnugrep}/bin/grep "$pci_device" | ${pkgs.gnugrep}/bin/grep -v "default_queue" | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.gnused}/bin/sed 's/://'); do
            if [[ -e "/proc/irq/$queue_irq/smp_affinity_list" ]]; then
              echo "$default_core" > "/proc/irq/$queue_irq/smp_affinity_list"
              echo "  Queue IRQ $queue_irq -> CPU $default_core"
            fi
          done
        fi

        wifi_count=$((wifi_count + 1))
      done
    else
      echo "Warning: No WiFi default queue IRQs found"
    fi

    echo "IRQ affinity configuration complete"
    echo "Current IRQ distribution:"
    cat /proc/interrupts | ${pkgs.gnugrep}/bin/grep -E "(enp|iwlwifi)" || true
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
      # Add capabilities needed for IRQ affinity
      CapabilityBoundingSet = [ "SYS_RAWIO" "SYS_ADMIN" ];
      AmbientCapabilities = [ "SYS_RAWIO" "SYS_ADMIN" ];
      # Run as root with proper permissions
      User = "root";
      Group = "root";
      # Allow new privileges (needed for IRQ affinity)
      NoNewPrivileges = false;
      # Add security options
      ProtectProc = "no";
      ReadWritePaths = [ "/proc/irq" ];
    };
  };
}

# end