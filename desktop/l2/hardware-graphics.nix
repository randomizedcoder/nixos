#
# NVIDIA CUDA compute configuration (headless, no display)
#
# RTX 3070 used only for llama.cpp compute
# AMD WX 2100 handles display
#

{ config, lib, pkgs, ... }:

{
  # Enable graphics/OpenGL for CUDA runtime
  hardware.graphics.enable = true;

  # Required to install nvidia driver (even for headless compute)
  services.xserver.videoDrivers = [ "nvidia" ];

  # Headless: no display manager or X server
  services.xserver.enable = false;
  services.displayManager.enable = false;

  # NVIDIA driver for compute only (open source kernel modules)
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = false;
    open = true;  # Open source kernel modules (supported on RTX 3070/Ampere)
  };

  # nvidia-smi for monitoring
  environment.systemPackages = [ pkgs.nvtopPackages.nvidia ];
}
