#
# arm/pi-bob/nix/monitoring.nix
#
# A self-contained monitoring stack for the Pi, all on the box itself:
#
#   node_exporter (:9100)  -->  Prometheus (:9090)  -->  Grafana (:3000)
#
# - node_exporter exposes host metrics (CPU, memory, disk, network, systemd...).
# - Prometheus scrapes it every 15s and stores the time series.
# - Grafana serves the web UI, is pre-wired to Prometheus as its default data
#   source, and auto-loads the "Node Exporter Full" dashboard (grafana.com
#   dashboard 1860) so there is something to look at on first login.
#
# Open http://pi-bob.local:3000  (or http://<pi-ip>:3000), log in as
# admin / admin (demo password - CHANGE IT), and open the "Node Exporter Full"
# dashboard.
#
# NOTE: Prometheus + Grafana write to /var/lib on the SD card continuously.
# That is fine for a demo, but on an SD card it does add steady write wear;
# retention is kept short (7d) to keep it modest. Drop this module if you don't
# want the monitoring stack.
#
{ config, pkgs, lib, ... }:

let
  # "Node Exporter Full" dashboard from grafana.com, pinned to a revision.
  # The published JSON references its Prometheus data source via a
  # "${DS_PROMETHEUS}" import input, which file-based provisioning does not
  # resolve. Rewrite those references to the dashboard's own `datasource`
  # template variable, which we point at the default (Prometheus) data source.
  nodeExporterDashboard = pkgs.runCommand "node-exporter-full.json"
    {
      src = pkgs.fetchurl {
        url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
        sha256 = "0qza4j8lywrj08bqbww52dgh2p2b9rkhq5p313g72i57lrlkacfl";
      };
    }
    ''
      sed 's|${"$"}{DS_PROMETHEUS}|${"$"}{datasource}|g' "$src" > "$out"
    '';

  nodePort = config.services.prometheus.exporters.node.port;
in
{
  # --- host metrics ---------------------------------------------------------
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    # Defaults are a good base; add systemd + per-process metrics.
    enabledCollectors = [
      "systemd"
      "processes"
    ];
    # Only Prometheus (on localhost) scrapes it, so no need to open the firewall.
    listenAddress = "127.0.0.1";
  };

  # --- metric store ---------------------------------------------------------
  services.prometheus = {
    enable = true;
    port = 9090;
    # Keep the on-SD TSDB small.
    retentionTime = "7d";
    globalConfig.scrape_interval = "15s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          { targets = [ "127.0.0.1:${toString nodePort}" ]; }
        ];
      }
    ];
  };

  # --- web UI ---------------------------------------------------------------
  services.grafana = {
    enable = true;
    settings = {
      server = {
        # Listen on all interfaces so the dashboard is reachable on the LAN.
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      # This is a lab/demo box - don't phone home.
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      # INSECURE demo credentials - change these (or set via a secret).
      security = {
        admin_user = "admin";
        admin_password = "admin";
        # Used to encrypt secrets in Grafana's DB. NixOS 26.05 removed the
        # built-in default, so we must set one. This demo value is world-
        # readable in the Nix store; for anything real, use a file-provider:
        #   secret_key = "$__file{/run/secrets/grafana-secret-key}";
        secret_key = "pleaseChangeMePiBobDemoSecretKey";
      };
    };

    provision = {
      enable = true;

      # Wire Grafana to Prometheus as the default data source.
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
        }
      ];

      # Auto-load any dashboard JSON dropped in /etc/grafana-dashboards.
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "default";
            options.path = "/etc/grafana-dashboards";
          }
        ];
      };
    };
  };

  # The dashboard JSON Grafana provisions from the path above.
  environment.etc."grafana-dashboards/node-exporter-full.json".source =
    nodeExporterDashboard;

  # Grafana web UI (and the Prometheus UI, handy for debugging queries).
  networking.firewall.allowedTCPPorts = [
    3000 # Grafana
    9090 # Prometheus (optional - remove to keep it internal)
  ];
}
