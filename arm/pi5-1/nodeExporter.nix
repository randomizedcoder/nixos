{ config, pkgs, ... }:
{
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/default.nix
  services.prometheus.exporters.node = {
    enable = true;
    port = 9000;
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters.nix
    enabledCollectors = [ "systemd" ];
    # /nix/store/zgsw0yx18v10xa58psanfabmg95nl2bb-node_exporter-1.8.1/bin/node_exporter  --help
    extraFlags = [
      "--collector.ethtool"
      "--collector.softirqs"
      "--collector.tcpstat"
      #"--collector.wifi"
      "--collector.filesystem.ignored-mount-points='/nix/store'"];
  };

  # https://search.nixos.org/options?channel=24.05&from=200&size=50&sort=relevance&type=packages&query=services.prometheus.exporters
  services.prometheus.exporters.systemd.enable = true;
  services.prometheus.exporters.smartctl.enable = true;
  services.prometheus.exporters.process.enable = true;
}