#
# qotom/nfb/chrony.nix
#
# Chrony NTP server configuration
# Syncs upstream to NTP pool and serves time to internal clients (e.g., Cisco ASA firewall)
#
# IMPORTANT: The NixOS chrony service module already defines comprehensive security features.
# Before adjusting this file, reference the upstream service module source:
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ntp/chrony.nix
#
# The upstream module configures:
# - ProtectSystem, ProtectHome, ProtectProc, ProcSubset
# - ReadWritePaths, ReadOnlyPaths
# - RestrictAddressFamilies
# - CapabilityBoundingSet (includes CAP_SYS_TIME and other necessary capabilities)
# - DeviceAllow (includes RTC devices)
# - SystemCallFilter (but includes @privileged)
# - All other standard security restrictions
#
# This file only customizes:
# - Resource limits (MemoryHigh, MemoryMax, CPUQuota, TasksMax)
# - SystemCallFilter (to exclude @privileged for better security score)
# - UMask (more restrictive than default)
#
# sudo systemctl status chronyd
# chronyc tracking
# chronyc -n sources

{ config, pkgs, lib, ... }:

let
  # Bind addresses for NTP server
  # Bind to all interfaces to serve time to internal clients
  # Alternatively, can bind to specific IP: [ "172.16.40.185" ]
  bindAddresses = [
    "0.0.0.0"  # IPv4 all interfaces
    "::"       # IPv6 all interfaces
  ];

  # Internal networks allowed to query this NTP server
  # Allow the management network where the firewall is located
  internalAllowFrom = [
    "172.16.40.0/24"  # Management network (includes firewall at 172.16.40.30)
    "127.0.0.0/8"     # Localhost
    "::1/128"         # IPv6 localhost
  ];
in {
  # Disable timesyncd as it conflicts with chrony
  services.timesyncd.enable = false;

  # Enable chrony NTP server
  services.chrony = {
    enable = true;

    # Use public NTP servers as upstream sources
    # North America NTP pool servers from https://www.ntppool.org/zone/north-america
    # Big list of public NTP servers
    # https://gist.github.com/mutin-sa/eea1c396b1e610a2da1e5550d94b0453
    servers = [
      "0.north-america.pool.ntp.org"
      "1.north-america.pool.ntp.org"
      "2.north-america.pool.ntp.org"
      "3.north-america.pool.ntp.org"
      "time.cloudflare.com"
      "time.google.com"
      "time.aws.com"
      "time.facebook.com"
    ];

    # Use iburst for rapid polling on startup
    serverOption = "iburst";

    # Enable memory locking for better performance
    enableMemoryLocking = true;

    # Enable RTC trimming for better timekeeping
    enableRTCTrimming = true;

    # Allow large time steps on startup (useful for VMs or systems that may be offline)
    initstepslew = {
      enabled = true;
      threshold = 1000;  # 1000 seconds threshold
    };

    # Extra configuration for internal NTP server
    extraConfig = ''
      # Bind to specific interfaces for internal NTP service
      ${lib.concatMapStringsSep "\n" (addr: "bindaddress ${addr}") bindAddresses}

      # Allow NTP queries from internal networks
      ${lib.concatMapStringsSep "\n" (range: "allow ${range}") internalAllowFrom}

      # Serve time even if not synchronized (useful for internal networks)
      local stratum 10

      # Enable NTP server mode
      port 123

      # Client access restrictions
      cmdallow 127.0.0.1
      cmdallow ::1

      # Key configuration for authentication (if needed)
      # keyfile /etc/chrony/chrony.keys
      # generatecommandkey
    '';
  };

  # Systemd service configuration with resource limits and priority
  # Note: Most security settings are already configured by the chrony service module
  # We only override/add what we need to customize
  # systemd-analyze security chronyd
  systemd.services.chronyd = {
    serviceConfig = {
      # Resource limits (not set by default service, so no mkForce needed)
      # Actual usage is ~9.5M, so set reasonable limits with headroom
      MemoryHigh = "20M";
      MemoryMax = "30M";
      CPUQuota = "20%";
      TasksMax = 100;

      # Process priority - NTP services should respond quickly even under system pressure
      # Lower nice value = higher priority (range: -20 to +19)
      # -10 is a good balance for NTP: high enough priority to respond quickly,
      # but not so high as to starve other important system services
      # Note: Negative nice values may require CAP_SYS_NICE capability, but the default
      # scheduling policy (CFS) with nice priority should be sufficient for NTP responsiveness
      Nice = -10;

      # Override SystemCallFilter to exclude @privileged for better security score
      # The default includes @privileged, we want to exclude it but keep necessary calls
      SystemCallFilter = lib.mkForce [
        "~@cpu-emulation"
        "~@debug"
        "~@keyring"
        "~@mount"
        "~@obsolete"
        "~@privileged"  # Exclude privileged system calls (improves security score)
        "~@resources"
        "@clock"        # Needed for time operations
        "@setuid"       # Needed for user switching
        "capset"        # Needed for capability management
        "@chown"        # Needed for file ownership changes
      ];

      # Override UMask for more restrictive permissions (default is "0027")
      UMask = lib.mkForce "0077";  # Owner-only access

      # Note: All other security settings (ProtectSystem, ProtectHome, etc.) are already
      # properly configured by the service module and don't need to be overridden
      # The service module also creates the necessary tmpfiles rules for /var/lib/chrony
    };
  };

  # Firewall rules for NTP
  networking.firewall.allowedUDPPorts = [ 123 ];  # NTP port
}

