#
# nixos/qotom/nfb/pdns-recursor.nix
#

# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/pdns-recursor.nix

{ config, lib, pkgs, ... }:

let

in {
  # PowerDNS Recursor
  # sudo lsof -i :53
  # systemctl status pdns-recursor
  # systemd-analyze security pdns-recursor
  #
  # IMPORTANT: This configuration binds to all interfaces (0.0.0.0 and ::)
  services.pdns-recursor = {
    enable = true;

    # Bind to all interfaces (not just loopback)
    # This allows pdns to respond on any IP address assigned to the machine,
    # including floating IPs moved by keepalived
    dns.address = [ "0.0.0.0" "::" ];

    # Allow from all internal network ranges
    # This includes management, VLAN, and WireGuard ranges (excluding bond0 which is external/WAN)
    # When keepalived moves IPs, clients in these internal ranges can query DNS
    dns.allowFrom = [ "0.0.0.0" "::" ];

    # # API configuration (for monitoring)
    api.address = "::1";
    api.port = 8082;
    api.allowFrom = [ "127.0.0.1" "::1" ];

    yaml-settings = {
      recursor = {
        serve_rfc1918 = true;
      };
    };

    # Export /etc/hosts entries
    #exportHosts = true;
  };

  users.users.pdns-recursor = {
    isSystemUser = true;
    group = "pdns-recursor";
    description = "PowerDNS Recursor daemon user";
  };

  users.groups.pdns-recursor = {};

  # Create required directories with correct ownership
  systemd.tmpfiles.rules = [
    "d /var/lib/pdns-recursor 0755 pdns-recursor pdns-recursor - -"
    "d /var/log/pdns-recursor 0755 pdns-recursor pdns-recursor - -"
    "d /run/pdns-recursor 0755 pdns-recursor pdns-recursor - -"
  ];

  # Systemd service configuration for pdns-recursor with resource limits
  systemd.services.pdns-recursor = {
    serviceConfig = {
      # Resource limits - DNS server needs many file descriptors for concurrent queries
      Slice = "pdns-recursor.slice";
      MemoryHigh = "150M";
      MemoryMax = "200M";
      CPUQuota = "15%";
      TasksMax = 100;  # Increased for concurrent DNS queries
      LimitNPROC = 200;  # Increased for concurrent processes
      LimitNOFILE = 16384;  # Significantly increased for many UDP sockets
      Nice = 10;

      # Security restrictions - DNS server needs minimal privileges
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      PrivateDevices = true;
      PrivateTmp = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      ProtectHostname = true;
      ProtectClock = true;
      MemoryDenyWriteExecute = true;
      UMask = "0027";

      # Network capabilities - DNS server needs minimal network access
      # CAP_NET_BIND_SERVICE: Required for binding to port 53
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

      # Address families - DNS server needs IPv4 and IPv6
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

      # System call architecture restrictions
      SystemCallArchitectures = [ "native" ];

      # System call filtering - DNS server needs minimal system calls
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@mount"
        "~@debug"
        "~@module"
        "~@reboot"
        "~@swap"
        "~@clock"
        "~@cpu-emulation"
        "~@obsolete"
        "~@raw-io"
        "~@resources"
      ];

      # File system restrictions
      ReadWritePaths = [
        "/var/lib/pdns-recursor"
        "/var/log"
        "/run"
        "/tmp"
      ];
      ReadOnlyPaths = [
        "/nix/store"
        "${pkgs.pdns-recursor}"
        "/etc/resolv.conf"
        "/etc/hosts"
        "/etc/nsswitch.conf"
        "/etc/ssl"
        "/etc/ca-bundle.crt"
        "/etc/ssl/certs"
      ];

      # User/group restrictions
      User = "pdns-recursor";
      Group = "pdns-recursor";

      # Runtime directory
      RuntimeDirectory = "pdns-recursor";

      # Restart policy
      Restart = "always";
      RestartSec = "1s";

      # Additional security measures
      RemoveIPC = true;  # Clean up IPC objects
      ProtectProc = "default";  # Allow access to process info and /proc/net
      ProcSubset = "pid";  # Only allow access to own process info

      # Environment
      Environment = [
        "PATH=${pkgs.pdns-recursor}/bin"
      ];
      PIDFile = "/run/pdns-recursor.pid";
    };
  };

  # Create dedicated slice for pdns-recursor
  systemd.slices.pdns-recursor = {
    description = "PowerDNS Recursor slice";
    sliceConfig = {
      MemoryHigh = "150M";
      MemoryMax = "200M";
      CPUQuota = "15%";
      TasksMax = 100;  # Increased for concurrent DNS queries
    };
  };

  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 8082 ];

  # Configure system to use local pdns-recursor
  #networking.nameservers = [ "::1" "127.0.0.1" ];
  networking.resolvconf.useLocalResolver = true;
  services.resolved.enable = false;

  environment.etc."resolv.conf".text = ''
    # pdns
    nameserver ::1
    nameserver 127.0.0.1
    # emergency cloudflare
    nameserver 2606:4700:4700::1111
    nameserver 1.1.1.1
    nameserver 8.8.8.8
  '';
}