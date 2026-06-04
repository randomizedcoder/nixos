{ config, pkgs, ... }:
{
  # https://nixos.wiki/wiki/Grafana
  # https://search.nixos.org/options?query=services.grafana
  services.grafana = {
    enable = true;
    settings = {
      server = {
        # Listening Address
        http_addr = "0.0.0.0";
        # and Port
        http_port = 3000;
        serve_from_sub_path = true;
        enable_gzip = true;
      };
    };
  };
}
