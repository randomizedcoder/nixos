{ config, pkgs, ... }:
{
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  services.prometheus.exporters.node = {
    enable = true;
    port = 9000;
    enabledCollectors = [ "systemd" ];
    extraFlags = [
      "--collector.ethtool"
      "--collector.softirqs"
      "--collector.tcpstat"
      "--collector.wifi"
      "--collector.filesystem.ignored-mount-points='/nix/store'"];
  };

  services.prometheus.exporters.systemd.enable = true;
  services.prometheus.exporters.smartctl.enable = true;
  services.prometheus.exporters.process.enable = true;
}
