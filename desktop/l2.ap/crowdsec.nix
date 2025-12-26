{ config, pkgs, ... }:

{
  # Enable CrowdSec engine with nftables integration
  services.crowdsec = {
    enable = true;

    # Allow access to local systemd journal
    allowLocalJournalAccess = true;

    # Configure data sources for threat detection
    acquisitions = [
      {
        source = "journalctl";
        journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
        labels.type = "syslog";
      }
      {
        source = "journalctl";
        journalctl_filter = ["_SYSTEMD_UNIT=systemd-logind.service"];
        labels.type = "syslog";
      }
    ];

    # Use flake defaults for all configuration
    settings = {
      # Only override the API server to use IPv6 localhost
      api = {
        server = {
          listen_uri = "[::1]:8080";
          # Trust localhost for API access (no API key needed for loopback)
          trusted_ips = [ "127.0.0.1" "::1" ];
        };
      };
    };
  };

  # Enable the firewall bouncer for CrowdSec with nftables support
  services.crowdsec-firewall-bouncer = {
    enable = true;

    # Use flake defaults for all configuration
    settings = {
      # Only override the API URL to use IPv6 localhost
      api_url = "http://[::1]:8080/";

      # Authentication settings for newer bouncer versions
      api_key = "ui00eX/NzDpjb6+m/xC+us1/SFHFNxQdOAmOqZur+4Y"; # Inscure!! Need to come up with a better way to handle this
      cert_path = "";  # Empty for localhost authentication
      key_path = "";   # Empty for localhost authentication

      # Disable TLS for localhost communication
      use_tls = false;
      ca_cert_path = "";

      # Use the same blacklist set names as our firewall
      blacklists_ipv4 = "blacklist";
      blacklists_ipv6 = "blacklist6";
    };
  };

  # Install CrowdSec CLI tools
  environment.systemPackages = with pkgs; [
    crowdsec
    crowdsec-firewall-bouncer
  ];

  # Add memory limits and Go memory environment variables to CrowdSec services
  # These are not set by the flake modules, so we can add them safely
  systemd.services.crowdsec = {
    serviceConfig = {
      # Memory limits for CrowdSec engine (log processing and threat detection)
      MemoryHigh = "512M";  # high water mark
      MemoryMax = "650M";   # hard limit
      # Go memory limit (90% of systemd limit)
      Environment = [ "GOMEMLIMIT=460MiB" ];  # 90% of 512MB
    };
  };

  systemd.services.crowdsec-firewall-bouncer = {
    serviceConfig = {
      # Memory limits for firewall bouncer (API polling and nftables management)
      MemoryHigh = "256M";  # high water mark
      MemoryMax = "400M";   # hard limit
      # Go memory limit (90% of systemd limit)
      Environment = [ "GOMEMLIMIT=230MiB" ];  # 90% of 256MB
    };
  };
}