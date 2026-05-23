#
# ClickHouse service with enhanced security restrictions
#

{ config, lib, pkgs, ... }:

let
  clickhouseDataDir = "/var/lib/clickhouse";
  clickhouseLogDir = "/var/log/clickhouse";
  clickhouseConfigDir = "/etc/clickhouse-server";
  clickhouseRunDir = "/run/clickhouse-server";

in {
  # Enable ClickHouse service
  services.clickhouse.enable = false;

  # Override the default ClickHouse service with enhanced security
  systemd.services.clickhouse = {

    serviceConfig = {
      # Resource limits - ClickHouse is memory and CPU intensive
      Slice = "clickhouse.slice";
      MemoryHigh = "2G";
      MemoryMax = "4G";
      CPUQuota = "50%";
      TasksMax = 50000;  # ClickHouse can spawn many threads (increased from 1000).  Clickhouse warns if this is below 30k.
      LimitNPROC = 50000;  # Increased for concurrent operations (increased from 2000)
      LimitNOFILE = 1048576; # 65536;  # ClickHouse needs many file descriptors
      Nice = 0;  # -20 is the highest priority, 0 is the default

      # Security restrictions - ClickHouse needs minimal privileges
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
      PrivateUsers = true;  # Create user namespace - service sees itself as root internally
      LockPersonality = true;
      ProtectHostname = true;
      ProtectClock = true;
      # MemoryDenyWriteExecute = true;  # Disabled for ClickHouse JIT compilation
      UMask = "0077";  # More restrictive: only owner can read/write ("0027" is the default, and allows group and other to read/write)

      # Network capabilities - ClickHouse needs network access for queries
      # CAP_NET_BIND_SERVICE: Required for binding to ports (default 9000, 8123)
      # CAP_SYS_NICE: Required for setting process priority
      # CAP_SYS_RESOURCE: Required for resource limits and CPU affinity
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_SYS_NICE" "CAP_SYS_RESOURCE" ];

      # Address families - ClickHouse needs IPv4 and IPv6
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

      # System call architecture restrictions
      SystemCallArchitectures = [ "native" ];

      # System call filtering - ClickHouse needs database-related system calls
      # Relaxed to allow CPU affinity and resource management
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@mount"
        "~@debug"
        "~@module"
        "~@reboot"
        "~@swap"
        "~@cpu-emulation"
        "~@obsolete"
        "~@raw-io"
        "~@resources"
        # Allow specific system calls that ClickHouse needs for CPU affinity and scheduling
        "sched_setaffinity"
        "sched_getaffinity"
        "setpriority"
        "getpriority"
        "sched_setparam"
        "sched_getparam"
        "sched_setscheduler"
        "sched_getscheduler"
        "sched_setattr"
        "sched_getattr"
        # Allow system calls needed for JIT compilation
        "mprotect"
        "mmap"
        "munmap"
      ];

      # File system restrictions
      ReadWritePaths = [
        clickhouseDataDir
        clickhouseLogDir
        clickhouseRunDir
        "/tmp"
        "/var/tmp"
        "/proc/self"
      ];
      ReadOnlyPaths = [
        "/nix/store"
        "${pkgs.clickhouse}"
        clickhouseConfigDir
        "/etc/resolv.conf"
        "/etc/hosts"
        "/etc/nsswitch.conf"
        "/etc/ssl"
        "/etc/ca-bundle.crt"
        "/etc/ssl/certs"
        "/usr/share/zoneinfo"
        "/etc/localtime"
      ];

      # User/group restrictions
      User = "clickhouse";
      Group = "clickhouse";

      # Runtime directory
      RuntimeDirectory = "clickhouse-server";

      # Restart policy
      Restart = "always";
      RestartSec = "1s";

      # Additional security measures
      RemoveIPC = true;  # Clean up IPC objects
      ProtectProc = "default";  # Allow access to process info and /proc/net
      ProcSubset = "pid";  # Only allow access to own process info

      # Environment
      Environment = [
        "PATH=${pkgs.clickhouse}/bin"
        "CLICKHOUSE_WATCHDOG_ENABLE=0"
      ];
      PIDFile = "${clickhouseRunDir}/clickhouse-server.pid";

      # Device access - ClickHouse doesn't need special device access
      DeviceAllow = [
        "/dev/null rw"
        "/dev/zero rw"
        "/dev/random r"
        "/dev/urandom r"
      ];

      # # IP address restrictions - Only allow local connections by default
      # # Modify this if you need external access
      # IPAddressAllow = [
      #   "localhost"
      #   "127.0.0.1"
      #   "::1"
      # ];
      # IPAddressDeny = [
      #   "any"
      # ];

      # Supplementary groups - ClickHouse doesn't need additional groups
      SupplementaryGroups = [];

      # Keyring mode - ClickHouse doesn't need keyring access
      KeyringMode = "private";

      # Delegate - ClickHouse doesn't need cgroup delegation
      Delegate = false;

      # Notify access - Only main process can alter service state
      NotifyAccess = "main";
    };
  };

  # Create dedicated slice for ClickHouse with resource limits
  systemd.slices.clickhouse = {
    description = "ClickHouse database slice";
    sliceConfig = {
      MemoryHigh = "2G";
      MemoryMax = "4G";
      CPUQuota = "50%";
      TasksMax = 50000;  # ClickHouse can spawn many threads (increased from 1000).  Clickhouse warns if this is below 30k.
    };
  };

  # Create required directories with correct ownership
  systemd.tmpfiles.rules = [
    "d ${clickhouseDataDir} 0755 clickhouse clickhouse - -"
    "d ${clickhouseLogDir} 0755 clickhouse clickhouse - -"
    "d ${clickhouseRunDir} 0755 clickhouse clickhouse - -"
    "d ${clickhouseConfigDir} 0755 clickhouse clickhouse - -"
  ];

  # Firewall rules for ClickHouse (only if you need external access)
  # By default, ClickHouse only listens on localhost
  # Uncomment and modify if you need external access
  # networking.firewall.allowedTCPPorts = [ 9000 8123 ];

  # # Additional security hardening
  # security.apparmor.enable = true;

  # Optional: Create AppArmor profile for ClickHouse
  # This would require additional configuration in a separate file
  # security.apparmor.profiles = {
  #   "clickhouse" = {
  #     profile = ''
  #       #include <tunables/global>
  #       profile clickhouse flags=(attach_disconnected) {
  #         #include <abstractions/base>
  #         #include <abstractions/nameservice>
  #
  #         ${clickhouseDataDir}/** rw,
  #         ${clickhouseLogDir}/** rw,
  #         ${clickhouseConfigDir}/** r,
  #         ${clickhouseRunDir}/** rw,
  #
  #         /nix/store/** r,
  #         /tmp/** rw,
  #         /var/tmp/** rw,
  #
  #         /proc/sys/kernel/hostname r,
  #         /proc/sys/kernel/random/uuid r,
  #         /proc/net/** r,
  #         /proc/self/** r,
  #
  #         /dev/null rw,
  #         /dev/zero r,
  #         /dev/random r,
  #         /dev/urandom r,
  #       }
  #     '';
  #   };
  # };
}
