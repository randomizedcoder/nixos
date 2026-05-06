#
# AMD GPU configuration for l2
#
# GPUs:
#   AMD WX 2100 (gfx803) - display output
#   AMD Radeon Pro W5700 (gfx1010) - compute
#   AMD Instinct MI50 (gfx906) - compute
#

{ config, lib, pkgs, ... }:

{
  hardware.graphics.enable = true;

  # AMD-only: no X server needed, amdgpu handles everything
  services.xserver.enable = false;
  services.displayManager.enable = false;
}
