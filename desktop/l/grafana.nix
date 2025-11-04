{ config, pkgs, ... }:
{
  # https://nixos.wiki/wiki/Grafana
  # https://search.nixos.org/options?query=services.grafana
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  # https://grafana.com/grafana/dashboards/1860-node-exporter-full/
  services.grafana = {
    enable = true;
    settings = {
      security.admin_password = "admin"; # this is my local only instance
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