{ config, pkgs, ... }:
{
  # Enable Hyprland system-wide
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };
}