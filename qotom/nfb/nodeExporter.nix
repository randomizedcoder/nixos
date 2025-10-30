#
# nixos/qotom/nfb/prometheus.nix
#
{ config, pkgs, ... }:
{
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/default.nix
  services.prometheus.exporters.node = {
    enable = true;
    port = 9000;
    listenAddress = "127.0.0.1"; # default is 0.0.0.0
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters.nix
    enabledCollectors = [ "systemd" ];
    extraFlags = [ "--collector.ethtool" "--collector.softirqs" "--collector.tcpstat" ]; # "--collector.wifi" ];
  };

  # Additional exporters
  services.prometheus.exporters.systemd.enable = true;
  services.prometheus.exporters.smartctl.enable = true;
  services.prometheus.exporters.process.enable = true;
}