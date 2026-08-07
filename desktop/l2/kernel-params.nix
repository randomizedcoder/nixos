# Kernel Parameters for L2
# CPU performance and GPU compute optimization

{ config, lib, pkgs, ... }:

{
  boot.kernelParams = [
    # CPU frequency scaling
    "cpufreq.default_governor=performance"

    # NUMA optimization
    "numa_balancing=0"

    # I/O scheduler
    "elevator=bfq"

    # IOMMU passthrough for ROCm GPU compute (MI50, W5700)
    "iommu=pt"
  ];

  # CPU frequency scaling
  powerManagement.cpuFreqGovernor = "performance";

  # Disable Bluetooth completely
  hardware.bluetooth.enable = false;
}