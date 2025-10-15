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

    # Configure DNS settings for proper DNSSEC validation
    settings = {
      # Enable DNSSEC validation
      dnssec = "validate";
      # Set query local address to enable IPv6 for outgoing queries
      query-local-address = "::";
      # Disable security polling to avoid external queries
      security-poll-suffix = "";
      # Configure forward zones for specific domains if needed
      # forward-zones = "example.com=172.16.50.1";
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
  networking.resolvconf.useLocalResolver = true;

  environment.etc."resolv.conf".text = ''
    # pdns
    nameserver ::1
    nameserver 127.0.0.1
    # emergency cloudflare
    nameserver 2606:4700:4700::1111
    nameserver 1.1.1.1
  '';
}