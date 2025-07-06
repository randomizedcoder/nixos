{ config, lib, pkgs, ... }:

{
  # PowerDNS Recursor configuration
  # This acts as a local DNS cache and forwards queries to 172.16.50.1
  services.pdns-recursor = {
    enable = true;

    # Bind to localhost only for security
    dns.address = [ "::1" "127.0.0.1" ];

    # Allow queries from localhost only
    dns.allowFrom = [ "127.0.0.0/8" "::1/128" ];

    # API configuration (for monitoring)
    api.address = "::1";
    api.port = 8082;
    api.allowFrom = [ "127.0.0.1" "::1" ];

    # Forward all zones to the upstream DNS server
    forwardZones = {
      "." = "172.16.50.1";  # Forward all queries to upstream DNS
    };

    # DNSSEC validation
    dnssecValidation = "validate";

    # Export /etc/hosts entries
    exportHosts = true;

    # Serve RFC1918 reverse zones locally
    serveRFC1918 = true;
  };

  # Firewall rules for pdns-recursor
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 8082 ];

  # Configure system to use local pdns-recursor
  networking.nameservers = [ "::1" "127.0.0.1" ];
  networking.resolvconf.useLocalResolver = true;
}