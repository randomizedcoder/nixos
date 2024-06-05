{ config, pkgs, ... }:
{
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  services.grafana = {
    enable = true;
    #domain = "grafana.pele";
    #port = 2342;
    #addr = "127.0.0.1";
  };
}