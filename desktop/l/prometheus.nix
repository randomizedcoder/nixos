{ config, pkgs, inputs, ... }:
{
  # https://wiki.nixos.org/wiki/Prometheus
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters-configuration
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/default.nix
  # default port 9090
  services.prometheus = {
    enable = true;
    globalConfig.scrape_interval = "10s"; # "1m"
    retentionTime = "90d";

    # urp exporter alert rules (design 39 §39.9), sourced from the upstream
    # uds-rdma-proxy flake input so they track the repo (git rev + narHash).
    # promtool checks these at build time.
    ruleFiles = [
      "${inputs.uds-rdma-proxy}/nix/urp-exporter-alerts.yml"
    ];

    scrapeConfigs = [
    {
      job_name = "node";
      static_configs = [{
        targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
      }];
    }
    # 2026-06-16: NVIDIA DCGM exporters. l serves on localhost; l2
    # serves on 0.0.0.0 (l reaches l2 via hosts.nix → 172.16.50.46).
    {
      job_name = "dcgm_l";
      static_configs = [{
        targets = [ "localhost:9400" ];
      }];
    }
    {
      job_name = "dcgm_l2";
      static_configs = [{
        targets = [ "l2:9400" ];
      }];
    }
    # urp metrics exporter (design 39) on the mesh nodes. Job MUST be "urp" so
    # the URPExporterDown alert's `up{job="urp"}` selector matches. Targets
    # resolve via hosts.nix (hp1/hp2/hp3 mgmt-LAN IPs). Until the exporter is
    # deployed to the hp nodes (design 39 PR5, listening on a mgmt-reachable
    # addr + openFirewall), these targets read DOWN — expected.
    {
      job_name = "urp";
      static_configs = [{
        targets = [ "hp1:9975" "hp2:9975" "hp3:9975" ];
      }];
    }
    # {
    #   job_name = "xtcp";
    #   static_configs = [{
    #     targets = [ "localhost:9088" ];
    #   }];
    # }
    # {
    #   job_name = "hp1_xtcp";
    #   static_configs = [{
    #     targets = [ "hp1:9088" ];
    #   }];
    # }
    # {
    #   job_name = "clickhouse";
    #   static_configs = [{
    #     #targets = [ "localhost:9363" ];
    #     targets = [ "localhost:19363" ];
    #   }];
    # }
    # {
    #   job_name = "hp1";
    #   static_configs = [{
    #     targets = [ "hp1:${toString config.services.prometheus.exporters.node.port}" ];
    #   }];
    # }
    # {
    #   job_name = "hp1_clickhouse";
    #   static_configs = [{
    #     #targets = [ "localhost:9363" ];
    #     targets = [ "hp1:19363" ];
    #   }];
    # }
    # {
    #   job_name = "hp2";
    #   static_configs = [{
    #     targets = [ "hp2:${toString config.services.prometheus.exporters.node.port}" ];
    #   }];
    # }
    # {
    #   job_name = "hp2_clickhouse";
    #   static_configs = [{
    #     #targets = [ "localhost:9363" ];
    #     targets = [ "hp2:19363" ];
    #   }];
    # }
    #{
    #  job_name = "chromebox1";
    #  static_configs = [{
    #    targets = [ "172.16.40.179:9105" ];
    #  }];
    #}
    ];
  };
}