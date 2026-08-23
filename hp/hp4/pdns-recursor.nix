{ config, lib, pkgs, ... }:

{
  # PowerDNS Recursor
  # This acts as a local DNS cache and forwards queries to 172.16.50.1
  # sudo lsof -i :53
  # systemctl status pdns-recursor
  services.pdns-recursor = {
    enable = true;

    # Bind to localhost only for security
    dns.address = [ "::1" "127.0.0.1" ];

    # Allow queries from localhost only
    dns.allowFrom = [ "::1/128" "127.0.0.0/8" ];

    # API configuration (for monitoring)
    api.address = "::1";
    api.port = 8082;
    api.allowFrom = [ "127.0.0.1" "::1" ];

    # DNSSEC validation. 26.05 / Recursor 5.x exposes this as the dedicated
    # `dnssecValidation` option (the module maps it to settings.dnssec.validation);
    # setting it under `settings` directly now collides with that internal definition.
    dnssecValidation = "validate";

    # Recursor 5.x replaced the flat pdns-recursor.conf keys with nested YAML
    # (pdns-recursor.yml). Migrated from the old 24.11 flat settings:
    #   query-local-address = "::"  -> outgoing.source_address (sequence)
    #   security-poll-suffix = ""   -> recursor.security_poll_suffix (string)
    #   dnssec = "validate"         -> dnssecValidation option above
    settings = {
      # Source outgoing queries from IPv6 (preserves the old query-local-address = "::").
      outgoing.source_address = [ "::" ];
      # Disable security-status polling so the recursor makes no external telemetry query.
      recursor.security_poll_suffix = "";
      # Configure forward zones for specific domains if needed
      # recursor.forward_zones = [ { zone = "example.com"; forwarders = [ "172.16.50.1" ]; } ];
    };

    # Export /etc/hosts entries
    exportHosts = true;

    # Serve RFC1918 reverse zones locally
    serveRFC1918 = true;
  };

  # Systemd service configuration for pdns-recursor with resource limits
  systemd.services.pdns-recursor = {
    serviceConfig = {
      # Resource limits - conservative for DNS service
      MemoryMax = "100M";
      MemoryHigh = "90M";
      CPUQuota = "15%";
      TasksMax = 50;

      # Process limits
      LimitNPROC = 100;

      # Nice priority
      Nice = 15;
    };
  };

  # Firewall rules for pdns-recursor
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 8082 ];

  # Configure system to use local pdns-recursor
  #networking.nameservers = [ "::1" "127.0.0.1" ];
  networking.nameservers = [ "172.16.50.1" ];
  # 26.05: resolvconf and a manual environment.etc."resolv.conf" now conflict (assertion).
  # We manage /etc/resolv.conf by hand below (already points at the local ::1/127.0.0.1
  # resolver), so disable resolvconf entirely rather than letting it fight us for the file.
  networking.resolvconf.enable = false;

  environment.etc."resolv.conf".text = ''
    # pdns
    nameserver ::1
    nameserver 127.0.0.1
    # emergency cloudflare
    nameserver 2606:4700:4700::1111
    nameserver 1.1.1.1
  '';
}