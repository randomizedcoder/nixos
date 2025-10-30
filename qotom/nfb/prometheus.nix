#
# nixos/qotom/nfb/prometheus.nix
#
{ config, pkgs, ... }:
{
  # https://wiki.nixos.org/wiki/Prometheus
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters-configuration
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/default.nix
  # default port 9090
  services.prometheus = {
    enable = true;
    globalConfig.scrape_interval = "10s"; # "1m"
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
      {
        job_name = "process";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.process.port}" ];
        }];
      }
      {
        job_name = "smartctl";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.smartctl.port}" ];
        }];
      }
      {
        job_name = "systemd";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.systemd.port}" ];
        }];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.nginx.port}" ];
        }];
      }
    ];
  };
}