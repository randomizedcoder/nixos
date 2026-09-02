{ ... }:

{
  # PowerDNS Recursor — the LAN's PRIMARY resolver for mgmt (VLAN 50) + devices
  # (VLAN 40); the UXG stays secondary. Validates DNSSEC (the UXG's dnsmasq only
  # forwards) and caches in RAM. Recurses to the roots — no forward zones.
  services.pdns-recursor = {
    enable = true;

    # Wildcard listen, gated by allowFrom — comes up regardless of when the LAN
    # addresses (.232 / ::232) are assigned and survives an ISP prefix change.
    # hp4 has no WAN interface and sits behind the UXG, so exposure is LAN-only,
    # further narrowed by allowFrom.
    dns.address = [ "0.0.0.0" "::" ];

    # Loopback + the two served VLANs (v4+v6). wemo (60) / dmz (66) stay on the
    # UXG for isolation. The v6 /64s ride the ISP prefix — MONITORING.md re-key runbook.
    dns.allowFrom = [
      "127.0.0.0/8" "::1/128"
      "172.16.50.0/24"                 # mgmt (VLAN 50)
      "172.16.40.0/24"                 # devices (VLAN 40)
      "2603:8002:ea00:6800::/64"       # mgmt v6
      "2603:8002:ea00:6801::/64"       # devices v6
    ];

    # Built-in webserver → Prometheus /metrics on [::1]:8082 (loopback, no api_key).
    # api.enable (our nixpkgs PR) isn't in this channel yet, so the enable flag is
    # set via settings.webservice.webserver below; swap to `api.enable = true` once merged.
    api.address = "::1";
    api.port = 8082;
    api.allowFrom = [ "127.0.0.1" "::1" ];

    dnssecValidation = "validate";

    settings = {
      recursor.security_poll_suffix = "";      # no version-check telemetry
      recursor.threads = 4;                     # LAN load; cache still ~1M default, capped by MemoryMax
      webservice.webserver = true;              # module renders api.* but never the enable flag
      recordcache.serve_stale_extensions = 30;  # serve expired answers (30 × 30s = 15 min) when auth servers are unreachable
    };

    exportHosts = true;      # resolve names from /etc/hosts
    serveRFC1918 = true;     # answer RFC1918 reverse zones locally
  };

  # Cache RAM headroom; run unthrottled (latency-sensitive). The module already
  # hardens the unit (systemd-analyze security: 1.9 OK); UMask tightens the last gap.
  systemd.services.pdns-recursor.serviceConfig = {
    MemoryHigh = "1536M";
    MemoryMax  = "2G";
    TasksMax   = 256;
    LimitNPROC = 512;
    UMask      = "0077";
  };

  # Only 53 needs a firewall hole; 8082 binds ::1 (loopback), reachable without one.
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # hp4 resolves via its own recursor first, Cloudflare as emergency. resolvconf is
  # off (it conflicts with a manual resolv.conf on 26.05), so write the file directly.
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".text = ''
    nameserver ::1
    nameserver 127.0.0.1
    nameserver 2606:4700:4700::1111
    nameserver 1.1.1.1
  '';
}
