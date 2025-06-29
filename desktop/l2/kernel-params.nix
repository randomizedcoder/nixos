# Kernel Parameters for L2 WiFi Access Point Optimization
# CPU isolation, network performance, and interrupt handling

{ config, lib, pkgs, ... }:

{
  # Boot kernel parameters for network optimization
  boot.kernelParams = [
    # CPU isolation for network cores (cache-aware, paired SMT siblings)
    "isolcpus=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
    "nohz_full=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
    "rcu_nocbs=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"

    # Interrupt handling
    "irqaffinity=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
    "threadirqs"

    # Memory management
    "hugepagesz=1G"
    "hugepages=4"

    # CPU frequency scaling
    "intel_pstate=performance"
    "cpufreq.default_governor=performance"

    # NUMA optimization
    "numa_balancing=0"

    # I/O scheduler
    "elevator=bfq"

    # Security mitigations (minimal impact on network performance)
    "mitigations=off"
    "spectre_v2=off"
    "spec_store_bypass_disable=off"
    "retbleed=off"

    # WiFi optimizations
    "cfg80211.ieee80211_regdom=US"
    "iwlwifi.power_save=0"
    "iwlwifi.11n_disable=0"
    "iwlwifi.bt_coex_active=0"

    # PCIe optimizations
    "pcie_aspm=off"
    "pcie_aspm.policy=performance"

    # Bluetooth disabling
    "bluetooth.blacklist=1"
    "btusb.blacklist=1"
    "btintel.blacklist=1"

    # Debugging (disable for production)
    "quiet"
    "loglevel=3"
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

        # Set min/max frequency to maximum for network cores (paired SMT siblings)
        for cpu in 0 12 1 13 2 14 3 15 4 16 5 17 6 18 7 19; do
          if [[ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq" ]]; then
            max_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq")
            echo "$max_freq" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null || true
            echo "$max_freq" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" 2>/dev/null || true
          fi
        done

        echo "CPU performance governor set for network optimization (paired SMT siblings)"
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