{ config, pkgs, lib, ... }:

let
  # Blackbox exporter hostname
  blackboxHost = "localhost:${toString config.services.prometheus.exporters.blackbox.port}";
  # SNMP exporter hostname (multi-target scrape passes device IP via __param_target)
  snmpHost = "localhost:${toString config.services.prometheus.exporters.snmp.port}";

in {
  # Prometheus configuration with blackbox integration
  # https://wiki.nixos.org/wiki/Prometheus
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters-configuration
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/default.nix
  # default port 9090
  services.prometheus = {
    enable = true;
    # openFirewall = true; # doesn't exist
    retentionTime = "90d"; # keep 90 days of history for network-device metrics
    globalConfig.scrape_interval = "10s"; # Keep node exporter at 10s
    scrapeConfigs = [
      # --- Network devices via SNMP (snmp_exporter multi-target) ---
      # CRS310 uses SNMPv3 (auth crs310_v3); Junipers use SNMPv2c (auth juniper_v2).
      # Two jobs because they need different `auth` params. See snmp-exporter.nix.
      {
        job_name = "snmp-crs310";
        metrics_path = "/snmp";
        params = { module = [ "if_mib" ]; auth = [ "crs310_v3" ]; };
        static_configs = [{ targets = [ "172.16.50.17" ]; }];
        relabel_configs = [
          { source_labels = [ "__address__" ]; target_label = "__param_target"; }
          { source_labels = [ "__param_target" ]; target_label = "instance"; }
          { target_label = "__address__"; replacement = snmpHost; }
        ];
      }
      {
        job_name = "snmp-juniper";
        metrics_path = "/snmp";
        params = { module = [ "if_mib" ]; auth = [ "juniper_v2" ]; };
        static_configs = [{ targets = [ "172.16.50.12" "172.16.50.11" ]; }];
        relabel_configs = [
          { source_labels = [ "__address__" ]; target_label = "__param_target"; }
          { source_labels = [ "__param_target" ]; target_label = "instance"; }
          { target_label = "__address__"; replacement = snmpHost; }
        ];
      }
      # --- UniFi (gateway, switches, APs, clients) via unpoller ---
      {
        job_name = "unpoller";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.unpoller.port}" ];
        }];
      }
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "localhost:9113" ];
        }];
      }
      {
        job_name = "blackbox_icmp_v4";
        metrics_path = "/probe";
        params = {
          module = [ "icmp_v4" ];
        };
        static_configs = [
          {
            targets = [ "8.8.8.8" "1.1.1.1" "142.250.190.78" ];
            labels = {
              job = "blackbox";
              category = "ICMP_IPv4";
            };
          }
        ];
        scrape_timeout = "10s";
        honor_labels = true;
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = blackboxHost;
          }
        ];
      }
      {
        job_name = "blackbox_icmp_v6";
        metrics_path = "/probe";
        params = {
          module = [ "icmp_v6" ];
        };
        static_configs = [
          {
            targets = [ "2001:4860:4860::8888" "2606:4700:4700::1111" "2607:f8b0:4007:811::200e" ];
            labels = {
              job = "blackbox";
              category = "ICMP_IPv6";
            };
          }
        ];
        scrape_timeout = "10s";
        honor_labels = true;
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = blackboxHost;
          }
        ];
      }
      {
        job_name = "blackbox_http";
        metrics_path = "/probe";
        params = {
          module = [ "http_2xx" ];
        };
        static_configs = [
          {
            targets = [ "google.com" "facebook.com" "yahoo.com" "ibm.com" ];
            labels = {
              job = "blackbox";
              category = "HTTP";
            };
          }
        ];
        scrape_timeout = "10s";
        honor_labels = true;
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = blackboxHost;
          }
        ];
      }
      {
        job_name = "blackbox_dns";
        metrics_path = "/probe";
        params = {
          module = [ "dns_udp_53" ];
        };
        static_configs = [
          {
            targets = [ "8.8.8.8" "1.1.1.1" "::1" ];
            labels = {
              job = "blackbox";
              category = "DNS";
            };
          }
        ];
        scrape_timeout = "10s";
        honor_labels = true;
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = blackboxHost;
          }
        ];
      }
    ];
  };

  # Systemd service configuration for Prometheus with security restrictions
  systemd.services.prometheus = {
    serviceConfig = {
      # Resource limits - generous for time series storage
      MemoryMax = "10G";
      MemoryHigh = "9.5G";
      CPUQuota = "50%";
      TasksMax = 500;

      # Process limits
      LimitNOFILE = 65536;
      LimitNPROC = 200;

      # Environment variable for Go memory limit (9GB = ~90% of 10GB limit)
      Environment = [ "GOMEMLIMIT=9GiB" ];

      # Nice priority
      Nice = 5;
    };
  };

  # Firewall rules for Prometheus
  networking.firewall.allowedTCPPorts = [ 9090 ];
}