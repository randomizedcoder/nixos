#
# arm/pi-sebastian/nix/home-das.nix
#
# das's home-manager config (the person who built and mailed this card).
# Starts from the shared baseline in home-common.nix.
#

{ config, pkgs, ... }:

{
  imports = [
    (import ./home-common.nix {
      username = "das";
      gitName = "randomizedcoder";
      gitEmail = "dave.seddon.ca@gmail.com";
    })
  ];

  # --- das's personal config -------------------------------------------------
  # home.packages = with pkgs; [ ];
}
