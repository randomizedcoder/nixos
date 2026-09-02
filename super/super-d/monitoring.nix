#
# /etc/nixos/monitoring.nix  —  identical on every super-* node
#
# System monitoring + diagnostics tooling for the super-* nodes, grouped in one module so
# it's clear what observability is installed. Companion to the firewall/tuning modules.
#
{ config, pkgs, lib, ... }:

let
  # The "small slice": HOUSEKEEPING cores only — cores 0-1 and their HT siblings 28-29.
  # Derived from the cpu-tuning.nix CPU map (reserved = 0-7,26-35,54-55 = 2 housekeeping +
  # 4 NIC-IRQ (2-5,30-33) + 2 RAID-IRQ (6-7,34-35) + 2 NVMe-IRQ (26-27,54-55)). Pinning the
  # `below` recorder here keeps it off BOTH the isolated k8s/DB pool (8-25,36-53) AND the
  # NIC/RAID/NVMe IRQ cores — so background sampling never steals cycles from the hot paths.
  # (Keep in sync with cpu-tuning.nix if that map changes.)
  housekeepingCpus = "0-1,28-29";
in
{
  # ── diagnostic / monitoring CLI tools ──
  environment.systemPackages = with pkgs; [
    nettools    # legacy net diagnostics: netstat, ifconfig, route, arp
    btop        # interactive resource monitor (CPU / mem / net / disk TUI)
  ];

  # ── below: Meta's resource-history recorder (atop-like) ──
  # `below record` continuously samples system state to /var/log/below; replay with the
  # `below` CLI (e.g. `below replay -t '5m ago'`). The recorder is background housekeeping,
  # so confine it to the housekeeping cores (it already inherits system.slice = the reserved
  # pool from cpu-tuning.nix; this narrows it further, off the IRQ cores too).
  services.below.enable = true;
  systemd.services.below.serviceConfig.AllowedCPUs = housekeepingCpus;
}
