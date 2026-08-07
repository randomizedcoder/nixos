{ config, pkgs, lib, ... }:

{
  # Intel Meteor Lake-P integrated graphics (Xe-LPG / Arc)
  # https://nixos.wiki/wiki/Intel_Graphics
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver        # iHD VAAPI driver (Broadwell+ / Meteor Lake)
      vpl-gpu-rt                # oneVPL runtime for newer Intel media stack
      libvdpau-va-gl
      intel-compute-runtime     # OpenCL on Intel iGPU
      vulkan-loader
    ];
  };

  # Force VAAPI to use the iHD driver (intel-media-driver) on Meteor Lake.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };
}
