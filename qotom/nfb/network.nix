#
# qotom/nfb/network.nix
#
# systemd-networkd configuration for Qotom nfb system
# Migrated from NetworkManager to systemd-networkd
#
# Network interfaces:
# - enp1s0: Currently active with 172.16.40.184/24 (management interface)
# - enp2s0, enp3s0, enp4s0: Available but not configured
#
# Based on example.network.nix with simplified configuration for this system

{ config, lib, pkgs, ... }:

{
  # Enable systemd-networkd
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network.enable = true;

  # Make networkd-wait-online more lenient
  systemd.services.systemd-networkd-wait-online = {
    serviceConfig = {
      # Don't fail if network isn't ready within timeout
      TimeoutStartSec = "30s";
      # Only wait for specific interfaces
      ExecStart = [
        ""
        "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --timeout=30 --any"
      ];
    };
  };

  # Configure systemd-networkd service to allow hostname setting
  # This is needed for proper network configuration
  systemd.services.systemd-networkd = {
    serviceConfig = {
      # Allow systemd-networkd to set the hostname (needed for DHCP)
      ProtectHostname = false;
      # Allow systemd-networkd to manage the hostname
      RestrictNamespaces = false;
      # Allow systemd-networkd to access the hostname
      RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
    };
  };

  # Network configuration
  systemd.network.networks = {
    # Management interface (enp1s0) - static IP configuration
    "mgmt" = {
      matchConfig.Name = "enp1s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        LLDP = true;
        EmitLLDP = true;
      };
      # networkConfig = {
      #   Address = [ "172.16.40.184/24" ];
      #   IPv6AcceptRA = true;
      #   IPv6PrivacyExtensions = true;
      #   LLDP = true;
      #   EmitLLDP = true;
      # };
      # routes = [
      #   {
      #     Gateway = "172.16.40.1";  # Assuming gateway is .1
      #     Destination = "0.0.0.0/0"; # Default route
      #     Metric = 100;
      #   }
      # ];
      linkConfig = {
        MTUBytes = 1500;
      };
    };

    # Additional interfaces - can be configured as needed
    # Currently set to DHCP for flexibility
    "enp2s0" = {
      matchConfig.Name = "enp2s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        LLDP = true;
        EmitLLDP = true;
      };
      linkConfig = {
        MTUBytes = 1500;
      };
    };

    "enp3s0" = {
      matchConfig.Name = "enp3s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        LLDP = true;
        EmitLLDP = true;
      };
      linkConfig = {
        MTUBytes = 1500;
      };
    };

    "enp4s0" = {
      matchConfig.Name = "enp4s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        LLDP = true;
        EmitLLDP = true;
      };
      linkConfig = {
        MTUBytes = 1500;
      };
    };
  };
}
