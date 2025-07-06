#
# https://gitlab.com/sidenio/nix/data_center/lax/dcops0_hp2/blackbox.nix
#

# Blackbox Exporter is our primary tool for network monitoring, providing:
# - ICMP ping monitoring (IPv4/IPv6)
# - HTTP/HTTPS monitoring
# - DNS resolution testing
# - Comprehensive metrics for Prometheus
#
# This configuration mirrors the monitoring setup in smokeping.nix but provides
# better integration with Prometheus and more detailed metrics.
#
# Monitoring Categories:
# 1. DNSServers - ICMP ping to DNS server IPs (connectivity)
# 2. Internet - ICMP ping to internet hosts (connectivity)
# 3. NetworkDevices - ICMP ping to local network devices (connectivity)
# 4. HTTP - HTTP monitoring of websites (service availability)
# 5. DNSLookup - DNS resolution testing using specific DNS servers
#
# https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/exporters/blackbox.nix

{ config, lib, pkgs, ... }:

let
  # Import WireGuard configuration to get peer information
  wireguardConfig = import ./wireguard.nix { inherit config lib pkgs; };

  # Helper function to detect if an address is IPv6
  isIPv6 = host: lib.hasInfix ":" host;

  # Helper function to determine protocol based on host address
  getProtocol = host: if isIPv6 host then "ip6" else "ip4";

  # Helper function to add protocol to target if not specified
  addProtocol = target: target // {
    protocol = target.protocol or (getProtocol target.host);
  };

  # Helper function to extract /32 IPs from allowedIPs
  extractSingleIPs = allowedIPs: lib.filter (ip: lib.hasSuffix "/32" ip) allowedIPs;

  # Helper function to convert CIDR to IP address
  cidrToIP = cidr: lib.head (lib.splitString "/" cidr);

  # Generate WireGuard peer targets from the wireguard configuration
  wireguardTargets = lib.mapAttrsToList (peerName: peer:
    lib.mapAttrsToList (ipName: ip: {
      name = "${peer.name} (${cidrToIP ip})";
      host = cidrToIP ip;
      peerName = peerName;
      cakePolicy = peer.cakePolicy;
    }) (lib.listToAttrs (map (ip: {
      name = ip;
      value = ip;
    }) (extractSingleIPs peer.allowedIPs)))
  ) wireguardConfig.wireguardPeers;

  # Flatten the nested list structure
  flatWireguardTargets = lib.flatten wireguardTargets;

  # Define targets in a structured way (matching smokeping.nix)
  targets = {
    # DNS Servers - ICMP ping testing
    "DNSServers" = {
      title = "DNS Server Connectivity (ICMP Ping)";
      menu = "DNS Servers";
      targets = {
        "Google_DNS_IPv4" = {
          name = "Google DNS IPv4";
          host = "8.8.8.8";
        };
        "Google_DNS_IPv6" = {
          name = "Google DNS IPv6";
          host = "2001:4860:4860::8888";
        };
        "Cloudflare_DNS_IPv4" = {
          name = "Cloudflare DNS IPv4";
          host = "1.1.1.1";
        };
        "Cloudflare_DNS_IPv6" = {
          name = "Cloudflare DNS IPv6";
          host = "2606:4700:4700::1111";
        };
        "Cloudflare_DNS_Secondary_IPv4" = {
          name = "Cloudflare DNS Secondary IPv4";
          host = "1.0.0.1";
        };
        "Cloudflare_DNS_Secondary_IPv6" = {
          name = "Cloudflare DNS Secondary IPv6";
          host = "2606:4700:4700::1001";
        };
      };
    };

    # Internet Connectivity
    "Internet" = {
      title = "Internet Connectivity Monitoring";
      menu = "Internet Connectivity";
      targets = {
        "Google_IPv4" = {
          name = "Google.com IPv4";
          host = "142.250.190.78";
        };
        "Google_IPv6" = {
          name = "Google.com IPv6";
          host = "2607:f8b0:4007:811::200e";
        };
        "Facebook_IPv6" = {
          name = "Facebook IPv6";
          host = "2a03:2880:f10d:183:face:b00c:0:25de";
        };
        "Yahoo_IPv6" = {
          name = "Yahoo IPv6";
          host = "2001:4998:24:120d::1:0";
        };
        "crowncastle-ic-386848" = {
          name = "crowncastle-ic-386848";
          host = "62.115.8.253";
        };
        "SidenLAX1" = {
          name = "SidenLAX1";
          host = "160.72.7.68";
        };
        "SidenLAX1_Internal" = {
          name = "SidenLAX1_Internal";
          host = "160.72.7.65";
        };
        "SidenLAX_dcops0_93" = {
          name = "SidenLAX_dcops0_93";
          host = "160.72.7.93";
        };
        "SidenLAX_dcops1_94" = {
          name = "SidenLAX_dcops1_94";
          host = "160.72.7.94";
        };
      };
    };

    # Network Devices and Gateways
    "NetworkDevices" = {
      title = "Network Devices and Gateways";
      menu = "Network Devices";
      targets = {
        "SpectrumLAG60_4" = {
          name = "SpectrumLAG60_4";
          host = "76.167.31.29";
        };
        "SpectrumLAG60_6" = {
          name = "SpectrumLAG60_6";
          host = "2605:e000:0:4::8:1d5";
        };
        "SpectrumGateway4" = {
          name = "SpectrumGateway4";
          host = "172.88.16.1";
        };
        "SpectrumGateway6" = {
          name = "SpectrumGateway6";
          host = "2605:e000:2fc0:f::1";
        };
        "RouterUSGdefault" = {
          name = "RouterUSGdefault";
          host = "172.16.50.1";
        };
        "Juniper2300" = {
          name = "Juniper2300";
          host = "172.16.50.12";
        };
        "Juniper2200_office" = {
          name = "Juniper2200-office";
          host = "172.16.50.11";
        };
      };
    };

    # HTTP Site Monitoring
    "HTTP" = {
      title = "HTTP Site Monitoring";
      menu = "HTTP Sites";
      targets = {
        "Google_HTTP" = {
          name = "Google HTTP";
          host = "google.com";
          probe = "http";
        };
        "IBM_HTTP" = {
          name = "IBM HTTP";
          host = "ibm.com";
          probe = "http";
        };
        "Yahoo_HTTP" = {
          name = "Yahoo HTTP";
          host = "yahoo.com";
          probe = "http";
        };
        "Facebook_HTTP" = {
          name = "Facebook HTTP";
          host = "facebook.com";
          probe = "http";
        };
      };
    };

    # DNS Resolution Testing
    "DNSLookup" = {
      title = "DNS Resolution Testing";
      menu = "DNS Resolution";
      targets = {
        "Google_DNS_Lookup" = {
          name = "Google DNS - google.com lookup";
          host = "8.8.8.8";
          probe = "dns";
          query = "google.com";
        };
        "Cloudflare_DNS_Lookup" = {
          name = "Cloudflare DNS - google.com lookup";
          host = "1.1.1.1";
          probe = "dns";
          query = "google.com";
        };
        "Local_DNS_Lookup" = {
          name = "Local DNS - google.com lookup";
          host = "::1";
          probe = "dns";
          query = "google.com";
        };
      };
    };
  };

  # Helper function to generate blackbox modules for ICMP targets
  generateICMPModules = categoryName: category:
    lib.mapAttrsToList (targetName: target:
      let targetWithProtocol = addProtocol target;
      in {
        name = "${categoryName}_${targetName}";
        prober = "icmp";
        icmp = {
          preferred_ip_protocol = "ip6";  # Prefer IPv6 when available
          count = 4;
        };
      }) category.targets;

  # Helper function to generate blackbox modules for HTTP targets
  generateHTTPModules = categoryName: category:
    lib.mapAttrsToList (targetName: target:
      if target ? probe && target.probe == "http" then {
        name = "${categoryName}_${targetName}";
        prober = "http";
        http = {
          preferred_ip_protocol = "ip6";  # Prefer IPv6 when available
          valid_status_codes = [ 200 301 302 303 307 308 ];
          fail_if_ssl = false;
          fail_if_not_ssl = false;
          method = "GET";
          headers = {
            User-Agent = "Prometheus/Blackbox Exporter";
          };
        };
      } else null) category.targets;

  # Helper function to generate blackbox modules for DNS targets
  generateDNSModules = categoryName: category:
    lib.mapAttrsToList (targetName: target:
      if target ? probe && target.probe == "dns" then {
        name = "${categoryName}_${targetName}";
        prober = "dns";
        dns = {
          preferred_ip_protocol = "ip6";  # Prefer IPv6 when available
          query_name = target.query;
          query_type = "A";
          valid_rcodes = [ "NOERROR" ];
        };
      } else null) category.targets;

  # Generate all blackbox modules
  icmpModules = lib.flatten (lib.mapAttrsToList generateICMPModules targets);
  httpModules = lib.flatten (lib.mapAttrsToList generateHTTPModules targets);
  dnsModules = lib.flatten (lib.mapAttrsToList generateDNSModules targets);

  # Filter out null values and combine all modules
  allBlackboxModules = lib.filter (module: module != null) (icmpModules ++ httpModules ++ dnsModules);

  # Generate blackbox configuration
  blackboxConfig = {
    modules = {
      # Simple ICMP module for testing
      "icmp_v4" = {
        prober = "icmp";
        icmp = {
          preferred_ip_protocol = "ip4";
        };
      };
      "icmp_v6" = {
        prober = "icmp";
        icmp = {
          preferred_ip_protocol = "ip6";
        };
      };
      "http_2xx" = {
        prober = "http";
        http = {
          preferred_ip_protocol = "ip4";
          valid_status_codes = [ 200 301 302 303 307 308 ];
        };
      };
      "dns_udp_53" = {
        prober = "dns";
        dns = {
          preferred_ip_protocol = "ip4";
          query_name = "google.com";
          query_type = "A";
          valid_rcodes = [ "NOERROR" ];
        };
      };
    };
  };

in {
  # Blackbox exporter configuration
  # systemctl status prometheus-blackbox-exporter
  # journalctl -u  prometheus-blackbox-exporter -f -n 20
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    listenAddress = "127.0.0.1";
    configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON blackboxConfig);
  };

  # Systemd service configuration for blackbox exporter with memory limits
  systemd.services.prometheus-blackbox-exporter = {
    serviceConfig = {
      # Resource limits
      MemoryMax = "300M";
      MemoryHigh = "280M";
      CPUQuota = "25%";
      TasksMax = 100;

      # Process limits
      LimitNOFILE = 1024;
      LimitNPROC = 50;

      # Environment variable for Go memory limit (260MB = ~90% of 300MB)
      Environment = [ "GOMEMLIMIT=260MiB" ];

      # Nice priority
      Nice = 10;
    };
  };

  # Export targets for use in prometheus.nix
  _module.args.blackboxTargets = targets;
  _module.args.wireguardTargets = flatWireguardTargets;

  # Firewall rules for blackbox exporter
  networking.firewall.allowedTCPPorts = [ 9115 ];
}