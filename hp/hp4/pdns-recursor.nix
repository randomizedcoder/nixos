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

    # DNSSEC validation defaults to "validate" via services.pdns-recursor.dnssecValidation.
    #
    # Recursor 5.x uses structured YAML: settings map 1:1 to recursor.yml sections
    # (with underscore-style keys), so the old flat settings must be nested.
    # https://doc.powerdns.com/recursor/yamlsettings.html
    settings = {
      outgoing = {
        # Enable IPv6 for outgoing queries. In Recursor 5.x YAML the old
        # query-local-address setting is outgoing.source_address.
        source_address = [ "::" ];
      };
      recursor = {
        # Disable security polling to avoid external queries (was security-poll-suffix)
        security_poll_suffix = "";
      };
      # Configure forward zones under recursor.forward_zones if needed
    };

    # Export /etc/hosts entries
    exportHosts = true;

    # Serve RFC1918 reverse zones locally
    serveRFC1918 = true;

    # This recursor only knows public DNS, so local ".home" names (served by the
    # gateway/DHCP resolver at 172.16.50.1) don't resolve on hp4 -- e.g.
    # opensprinkler.home. Forward the "home" zone to the gateway (recurse form
    # sets the recursion-desired bit, since the gateway is itself a resolver).
    forwardZonesRecurse = {
      "home" = "172.16.50.1";
    };

    # The gateway's "home" zone is unsigned, but this recursor validates DNSSEC,
    # so it rejects those answers as bogus (SERVFAIL, EDE 12 "NSEC Missing").
    # A negative trust anchor tells the recursor to treat "home" as insecure
    # (skip validation) rather than fail it.
    luaConfig = ''
      addNTA("home", "local unsigned zone served by the gateway")
    '';
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
  # We manage /etc/resolv.conf directly below, so resolvconf must be disabled
  # (nixpkgs now asserts against having both). useLocalResolver is redundant
  # since the manual file already points at the local recursor.
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