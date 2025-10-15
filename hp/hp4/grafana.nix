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
        admin_password = "adin";  # Change this to your desired password
        admin_email = "admin@localhost";
        # Disable initial admin creation to prevent password resets
        disable_initial_admin_creation = false;
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
  };
}