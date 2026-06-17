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
    # Previous: nixpkgs `stable` channel (was driver 595.80 at time of
    # switch). Kept commented for quick revert if 610.x regresses.
    #package = config.boot.kernelPackages.nvidiaPackages.stable;
    # 2026-06-14: experimenting with newer kernel + driver combo.
    # `latest` resolved to 610.43.02 in this nixpkgs. Pairs with
    # linuxPackages_latest in configuration.nix.
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    modesetting.enable = false;  # headless compute, no display output
    open = true;  # Open source kernel modules (supported on RTX 3070/Ampere)
  };

  # nvidia-smi and nvtop for monitoring
  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];
}
