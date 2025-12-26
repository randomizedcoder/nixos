#
# hp/hp1/networkd.nix
#
# systemd-networkd configuration for hp1
# - eno1: IPv4 DHCP + SLAAC IPv6
# - enp1s0f0, enp1s0f1, enp4s0f0, enp4s0f1: Unmanaged (for bridge/manual configuration)
#
# networkctl status --all

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
    # eno1: Main interface with IPv4 DHCP and SLAAC IPv6
    "eno1" = {
      matchConfig.Name = "eno1";
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

    # Bridge interfaces - unmanaged (handled by bridge service)
    "enp1s0f0" = {
      matchConfig.Name = "enp1s0f0";
      linkConfig = {
        Unmanaged = true;
      };
    };

    "enp1s0f1" = {
      matchConfig.Name = "enp1s0f1";
      linkConfig = {
        Unmanaged = true;
      };
    };

    # 10GE interfaces - unmanaged (for manual configuration)
    "enp4s0f0" = {
      matchConfig.Name = "enp4s0f0";
      linkConfig = {
        Unmanaged = true;
      };
    };

    "enp4s0f1" = {
      matchConfig.Name = "enp4s0f1";
      linkConfig = {
        Unmanaged = true;
      };
    };
  };
}

