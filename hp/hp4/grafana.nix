{ config, pkgs, ... }:
{
  # https://nixos.wiki/wiki/Grafana
  # https://search.nixos.org/options?query=services.grafana
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  # https://grafana.com/grafana/dashboards/1860-node-exporter-full/
  # https://grafana.com/grafana/dashboards/7587-prometheus-blackbox-exporter/
  # https://grafana.com/grafana/dashboards/14928-prometheus-blackbox-exporter/
  services.grafana = {
    enable = true;
    #openFirewall = true; # this doesn't exist
    settings = {
      server = {
        # Listening Address
        http_addr = "0.0.0.0";
        # and Port
        http_port = 3000;
        # Grafana needs to know on which domain and URL it's running
        #domain = "your.domain";
        #root_url = "https://your.domain/grafana/"; # Not needed if it is `https://your.domain/`
        serve_from_sub_path = true;
        enable_gzip = true;
      };

      # Security settings - set persistent admin password
      security = {
        admin_user = "admin";
        admin_password = "admin";  # Change this to your desired password
        admin_email = "admin@localhost";
        # Disable initial admin creation to prevent password resets
        disable_initial_admin_creation = false;
        # 26.05 requires an explicit secret_key (the built-in default was removed).
        # This is a LAN monitoring box whose Grafana DB holds nothing sensitive
        # (datasources/dashboards are provisioned declaratively, no stored creds), and
        # admin_password is already "admin" above — so we pin the old built-in default
        # value. This keeps any already-encrypted DB secrets decryptable across the
        # upgrade. Switch to a file-provider ($__env) if real secrets ever land here.
        secret_key = "SW2YcwTIb9zpOOhoPsMm";
      };

      # User settings
      users = {
        # Allow sign up (optional - set to false for more security)
        allow_sign_up = false;
        # Auto assign new users to main organization
        auto_assign_org = true;
        # Default role for new users
        auto_assign_org_role = "Viewer";
      };
    };

    # Declarative provisioning: Prometheus datasource + dashboards from ./dashboards
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [{
          name = "Prometheus";
          uid = "prometheus";          # dashboards reference this uid
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
        }];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [{
          name = "sansovino-network";
          type = "file";
          options.path = ./dashboards;   # dir of *.json, copied into the nix store
        }];
      };
    };
  };
}