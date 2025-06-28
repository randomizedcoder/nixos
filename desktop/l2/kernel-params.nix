# Kernel Parameters for L2 WiFi Access Point Optimization
# CPU isolation, network performance, and interrupt handling

{ config, lib, pkgs, ... }:

{
  # Boot kernel parameters for network optimization
  boot.kernelParams = [
    # CPU isolation for network cores
    "isolcpus=0-7"           # Isolate cores 0-7 from scheduler
    "nohz_full=0-7"          # Disable tick for network cores
    "rcu_nocbs=0-7"          # Disable RCU callbacks on network cores

    # Interrupt handling
    "irqaffinity=0-7"        # Default IRQ affinity to network cores
    "threadirqs"             # Threaded IRQs for better performance

    # Memory management
    "hugepagesz=1G"          # 1GB huge pages for network buffers
    "hugepages=4"            # Allocate 4 huge pages

    # CPU frequency scaling
    "intel_pstate=performance"  # Performance governor
    "cpufreq.default_governor=performance"

    # NUMA optimization
    "numa_balancing=0"       # Disable automatic NUMA balancing

    # I/O scheduler
    "elevator=bfq"           # Budget Fair Queueing scheduler

    # Security mitigations (minimal impact on network performance)
    "mitigations=off"        # Disable security mitigations for performance
    "spectre_v2=off"
    "spec_store_bypass_disable=off"
    "retbleed=off"

    # WiFi optimizations
    "cfg80211.ieee80211_regdom=US"            # Set regulatory domain
    "iwlwifi.power_save=0"                    # Disable power saving
    "iwlwifi.11n_disable=0"                   # Enable 802.11n
    "iwlwifi.bt_coex_active=0"                # Disable Bluetooth coexistence

    # PCIe optimizations
    "pcie_aspm=off"                           # Disable ASPM for performance
    "pcie_aspm.policy=performance"            # Performance policy

    # Bluetooth disabling
    "bluetooth.blacklist=1"                   # Disable Bluetooth
    "btusb.blacklist=1"                       # Disable USB Bluetooth
    "btintel.blacklist=1"                     # Disable Intel Bluetooth

    # Debugging (disable for production)
    "quiet"                                   # Quiet boot
    "loglevel=3"                              # Reduce log level
  ];

  # CPU frequency scaling
  powerManagement.cpuFreqGovernor = "performance";

  # Disable CPU frequency scaling for network cores
  systemd.services.cpu-performance = {
    description = "Set CPU performance governor for network cores";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "cpu-performance" ''
        #!/bin/bash
        # Set performance governor for all CPUs
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          echo performance > "$cpu" 2>/dev/null || true
        done

        # Set minimum and maximum frequency to maximum for network cores
        for cpu in {0..7}; do
          if [[ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq" ]]; then
            max_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq")
            echo "$max_freq" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null || true
            echo "$max_freq" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" 2>/dev/null || true
          fi
        done

        echo "CPU performance governor set for network optimization"
      '';
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Disable Bluetooth completely
  hardware.bluetooth.enable = false;

  # Disable Bluetooth kernel modules
  boot.blacklistedKernelModules = [
    "bluetooth"
    "btusb"
    "btintel"
    "btrtl"
    "btbcm"
    "btqca"
    "hci_uart"
    "hci_vhci"
    "hci_h4"
    "hci_bcsp"
    "hci_ll"
    "hci_mrvl"
    "hci_qca"
    "hci_uart"
    "hci_vhci"
    "hci_h4"
    "hci_bcsp"
    "hci_ll"
    "hci_mrvl"
    "hci_qca"
  ];
}