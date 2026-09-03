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
        job_name = "mq-cake";
        static_configs = [{
          targets = [ "localhost:2112" ];
        }];
      }
      # agent-seddon: `--serve-all` exposes /metrics on :9700 and
      # `--serve-sessions` on :9630 (ports from the repo's nix/constants.nix —
      # gateway.metrics_port / sessions metrics_port). These feed the portal's
      # gRPC p50/p99 status cell and any Grafana dashboards. DOWN until those
      # processes run.
      {
        job_name = "agent-gateway";
        static_configs = [{
          targets = [ "127.0.0.1:9700" ];
        }];
      }
      {
        job_name = "agent-sessions";
        static_configs = [{
          targets = [ "127.0.0.1:9630" ];
        }];
      }
    ];
  };
}