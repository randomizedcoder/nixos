{ config, pkgs, ... }:
# Prometheus SNMP exporter for the non-UniFi network devices.
#   CRS310  (172.16.50.17)  -> SNMPv3 authPriv, auth "crs310_v3"
#   EX2300  (172.16.50.12)  -> SNMPv2c,        auth "juniper_v2"
#   EX2200  (172.16.50.11)  -> SNMPv2c,        auth "juniper_v2"
#
# Config lives in ./snmp.yml (if_mib module + the two auths). Secrets are NOT in
# that file — they are ${VAR} placeholders expanded from environmentFile at runtime:
#   SNMPV3_AUTH_PASS, SNMPV3_PRIV_PASS  (CRS310 v3 SHA/AES passwords)
#   V2_COMMUNITY                        (Juniper read-only community)
# Create /etc/snmp-exporter.env on hp4 (mode 0400, root) with those KEY=VALUE lines.
#
# Prometheus scrapes it via the multi-target pattern (see prometheus.nix jobs
# snmp-crs310 / snmp-juniper). Bound to localhost only.
{
  # Upstream snmp_exporter's --config.expand-environment-variables only expands
  # ${VAR} in username/password/priv_password, NOT in `community` — so the
  # Juniper SNMPv2c community (${V2_COMMUNITY}) was sent to the device verbatim
  # and every v2c scrape failed with "request timeout (after 3 retries)".
  # Patch adds community expansion (submitted upstream: prometheus/snmp_exporter#1679).
  # The patch touches only config/config.go (not go.mod/go.sum), so vendorHash is
  # unchanged. The module hardcodes pkgs.prometheus-snmp-exporter (no `package`
  # option), so override it via an overlay.
  nixpkgs.overlays = [
    (final: prev: {
      prometheus-snmp-exporter = prev.prometheus-snmp-exporter.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./snmp-exporter-expand-community.patch ];
      });
    })
  ];

  services.prometheus.exporters.snmp = {
    enable = true;
    port = 9116;
    listenAddress = "127.0.0.1";
    configurationPath = ./snmp.yml;
    environmentFile = "/etc/snmp-exporter.env";
    # The snmp.yml uses ${VAR} placeholders; the build-time dry-run check can't
    # expand them, so disable it (config is validated at service start instead).
    enableConfigCheck = false;
  };
}
