#
# arm/pi5-1/configuration.nix
#

{ config, pkgs, lib, ... }:

# https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
# https://discourse.nixos.org/t/differences-between-nix-channels/13998

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [
      ./sysctl.nix
      ./services.ssh.nix
      ./nodeExporter.nix
      ./docker-daemon.nix
    ];

  # https://nixos.wiki/wiki/Nix_Cookbook
  nix = {
    settings = {
      auto-optimise-store = true;
      #experimental-features = [ "nix-command" "flakes" ];
      experimental-features = [ "nix-command" "flakes" ];

      download-buffer-size = "100000000";
    };

    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "weekly";                  # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

  networking.firewall.enable = true;

  services.lldpd.enable = true;

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  nixpkgs.config = {
    allowUnfree = true;
  };
}