{ config, pkgs, ... }:
# Prometheus UniFi Poller (unpoller) — pulls per-device + per-client metrics from
# the UniFi controller API. Covers the Gateway Pro, both UniFi switches, all 10 APs,
# and clients — richer than SNMP, and UniFi is deprecating SNMP anyway.
#
# AUTH: unpoller does NOT support the integration API key — it logs in with a UniFi
# LOCAL admin (read-only is enough). Create a local account (e.g. "unpoller") on the
# controller first. The password is read from a FILE (not inline):
#   echo -n '<password>' > /etc/unpoller-pass   # on hp4, mode 0400, readable by the exporter
#
# Exposes metrics on :9130 (scraped by the prometheus "unpoller" job). localhost only
# via the scrape; the controller connection is outbound to 172.16.50.5.
{
  services.prometheus.exporters.unpoller = {
    enable = true;
    port = 9130;
    controllers = [
      {
        url = "https://172.16.50.5";
        user = "unpoller";
        pass = "/etc/unpoller-pass";   # path to a file containing the password
        verify_ssl = false;            # controller uses a self-signed cert
        save_dpi = true;               # per-client DPI (app) metrics
        save_sites = true;
        sites = [ "all" ];
      }
    ];
  };
}
