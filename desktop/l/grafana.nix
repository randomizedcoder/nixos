{ config, pkgs, inputs, ... }:
let
  # Expose ONLY the urp dashboard JSON in a directory for Grafana's file
  # provider (it loads every *.json under the path). Sourced from the upstream
  # uds-rdma-proxy flake input so it tracks the repo (git rev + narHash).
  urpDashboards = pkgs.linkFarm "urp-grafana-dashboards" [
    {
      name = "urp-exporter-dashboard.json";
      path = "${inputs.uds-rdma-proxy}/nix/urp-exporter-dashboard.json";
    }
  ];
in
{
  # https://nixos.wiki/wiki/Grafana
  # https://search.nixos.org/options?query=services.grafana
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  # https://grafana.com/grafana/dashboards/1860-node-exporter-full/
  services.grafana = {
    enable = true;

    # Provision a Prometheus datasource + the urp dashboard (design 39) so the
    # metrics-exporter view is present without any manual UI import. The
    # dashboard's `datasource` template variable resolves to the default DS.
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "urp";
          options.path = urpDashboards;
        }
      ];
    };

    settings = {
      security.admin_password = "admin"; # this is my local only instance
      security.secret_key = "admin"; # required since nixpkgs 2025+, local-only instance
      users.password_hint = "admin";
      server = {
        # Listening Address
        http_addr = "127.0.0.1";
        # and Port
        http_port = 3000;
        # Grafana needs to know on which domain and URL it's running
        #domain = "your.domain";
        #root_url = "https://your.domain/grafana/"; # Not needed if it is `https://your.domain/`
        serve_from_sub_path = true;
        enable_gzip = true;
      };
    };
  };
}
