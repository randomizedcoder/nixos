{ config, pkgs, ... }:
{
  # https://wiki.nixos.org/wiki/Prometheus
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters-configuration
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/default.nix
  # default port 9090
  services.prometheus = {
    enable = true;
    globalConfig.scrape_interval = "10s"; # "1m"
    retentionTime = "90d";
    scrapeConfigs = [
    {
      job_name = "node";
      static_configs = [{
        targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
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