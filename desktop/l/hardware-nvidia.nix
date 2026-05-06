#
# NVIDIA RTX 3070 compute configuration (headless, no display)
#
# RTX 3070 (PCI 41:00.0) used only for llama.cpp CUDA compute
# AMD W7500 (PCI 63:00.0) handles display via GNOME/GDM
#
# Check: nvidia-smi
# Monitor: nvtop
#

{ config, lib, pkgs, ... }:

{
  # NVIDIA driver for compute only (open source kernel modules)
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = false;  # headless compute, no display output
    open = true;  # Open source kernel modules (supported on RTX 3070/Ampere)
  };

  # nvidia-smi and nvtop for monitoring
  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];
}
