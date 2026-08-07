#
# below.nix
#
# systemctl status below
#
{ config, pkgs, ... }:
{
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/monitoring/below.nix
  services.below = {
    enable = true;

    # Enable all collection options
    collect = {
      diskStats = true;   # Enable disk_stat collection (default: true)
      ioStats = true;     # Enable io.stat collection for cgroups
      exitStats = true;   # Enable eBPF-based exitstats (default: true)
    };

    # Enable data compression to save storage space
    compression.enable = true;

    # Retain data for 7 days (604800 seconds = 7 * 24 * 3600)
    retention.time = 604800;
  };
}