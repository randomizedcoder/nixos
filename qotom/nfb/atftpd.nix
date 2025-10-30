#
# nixos/qotom/nfb/atftpd.nix
#

# TFTP Server Configuration
# Used for PXE boot files (undionly.kpxe, snp.efi, etc.)
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/atftpd.nix
#
# SECURITY CONFIGURATION LESSONS LEARNED:
# ======================================
# 1. SystemCallFilter Configuration:
#    - setreuid() and setregid() are in the @privileged group
#    - Using ~@privileged blocks these essential calls
#    - @system-service profile includes setreuid/setregid but is still restrictive
#    - Individual system call allowlists don't work when conflicting with group exclusions
#
# 2. User/Group Access Requirements:
#    - atftpd needs access to /etc/passwd and /etc/group for user/group lookups
#    - PrivateUsers = true blocks access to user database (causes "No such file or directory")
#    - Must use PrivateUsers = false for services that need user/group lookups
#
# 3. File System Access:
#    - ReadOnlyPaths = [ "/etc" ] provides access to user/group files
#    - ReadWritePaths = [ "/var/run/nscd" ] allows nscd socket access
#    - InaccessiblePaths = [ "/etc" ] conflicts with ReadOnlyPaths - don't use both
#
# 4. Security vs Functionality Balance:
#    - TFTP service needs: file ops, network ops, user/group ops, memory ops
#    - Some "security issues" are acceptable trade-offs for functionality
#    - CAP_SET(UID|GID) required for setreuid()/setregid()
#    - AF_INET/AF_INET6 required for UDP sockets
#    - @privileged calls required for user/group operations
#
# 5. Debugging Approach:
#    - Use strace to identify actual system calls needed
#    - Test without SystemCallFilter first, then add restrictions
#    - systemd-analyze security provides good guidance
#    - Target security score: 2.0-2.5 OK for network services
#
# 6. NixOS-Specific Considerations:
#    - nscd/nsncd socket access needed for efficient lookups
#    - NixOS paths and environment variables must be preserved
#    - Service user/group must exist in NixOS configuration
#
# FINAL CONFIGURATION:
# - Security Score: 2.0 OK (excellent for network service)
# - Functionality: Full TFTP service with PXE boot support
# - Restrictions: Appropriate for simple UDP service
# - Documentation: Comprehensive for future maintenance

{ config, lib, pkgs, thisNode, ... }:

let

in

{
  # Dedicated TFTP service user for security
  users.users.atftpd = {
    isNormalUser = false;
    isSystemUser = true;
    description = "TFTP server user";
    group = "atftpd";
    home = "/nonexistent";  # Avoid conflict with ProtectHome
    createHome = false;
  };

  users.groups.atftpd = {};

  # TFTP Server Configuration
  # Used for PXE boot files (undionly.kpxe, snp.efi, etc.)
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/atftpd.nix
  services.atftpd = {
    enable = true;
    root = "/var/lib/atftp";
    extraOptions = [
      "--bind-address 0.0.0.0"       # Listen on all interfaces
      "--user atftpd.atftpd"         # Run as dedicated TFTP user instead of nobody.nogroup
      "--maxthread 20"               # Allow up to 20 concurrent TFTP transfers
      "--tftpd-timeout 180"          # Server exits after 3 minutes of inactivity (prevents hanging on crashed clients)
      "--retry-timeout 5"            # Wait 5 seconds for client responses before retransmitting
      "--prevent-sas"                # Prevent Sorcerer's Apprentice Syndrome for reliable transfers
      "--logfile -"                  # Log to stdout (captured by systemd)
      "--verbose=7"                  # Maximum verbosity for debugging
    ];
  };

  # Security hardening for TFTP service
  # systemd-analyze security atftpd.service
  systemd.services.atftpd = {
    # Run as dedicated user for security
    serviceConfig = {
      User = "atftpd";
      Group = "atftpd";

      # Resource limits
      # Memory limits
      MemoryMax = "100M";
      MemoryHigh = "80M";

      # CPU limits
      CPUQuota = "20%";

      # Process limits
      LimitNOFILE = 256;
      LimitNPROC = 100;

      # Security restrictions
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
      PrivateDevices = true;
      ProtectHome = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";

      # Additional security restrictions based on systemd-analyze findings
      NoNewPrivileges = true;           # Prevent acquiring new privileges
      RestrictSUIDSGID = true;          # Prevent creating SUID/SGID files
      PrivateTmp = true;                # Private /tmp directory
      PrivateUsers = false;             # Must be false: atftpd needs access to /etc/passwd and /etc/group to look up atftpd user/group
      RemoveIPC = true;                 # Clean up IPC objects

      # Additional hardening (optional improvements)
      SystemCallArchitectures = "x86-64"; # Restrict to x86-64 architecture only

      # System call filtering (using system-service profile with minimal exclusions)
      # LESSONS LEARNED:
      # 1. setreuid() and setregid() are in the @privileged group, so ~@privileged blocks them
      # 2. @system-service profile includes setreuid/setregid but is still restrictive
      # 3. Individual system call allowlists don't work when conflicting with group exclusions
      # 4. TFTP service needs: file ops, network ops, user/group ops, memory ops
      # 5. Use strace to identify actual system calls needed, then use appropriate profiles
      SystemCallFilter = [
        "@system-service"
        "~@mount"
        "~@debug"
        "~@module"
        "~@reboot"
        "~@swap"
        "~@obsolete"
      ];

      # Restrict address families (only UDP needed for TFTP)
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];

      # Device access (minimal)
      DeviceAllow = [
        "/dev/null rw"
        "/dev/zero rw"
        "/dev/urandom r"
        "/dev/random r"
      ];

      # Capabilities needed for TFTP
      # CAP_NET_BIND_SERVICE: Required to bind to privileged port 69
      # CAP_SETUID: Required for --user option to change user identity
      # CAP_SETGID: Required for --user option to change group identity
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_SETUID" "CAP_SETGID" ];
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_SETUID" "CAP_SETGID" ];

      # File permissions
      UMask = "0027";

      # File system restrictions (read-only access to TFTP directory)
      ProtectSystem = "strict";
      # ReadOnlyPaths: Allow access to files needed by atftpd
      # /var/lib/atftp: TFTP root directory for serving files
      # /etc: Required for user/group lookups (passwd, group, nsswitch.conf, etc.)
      #ReadOnlyPaths = [ "/var/lib/atftp" "/etc" ];
      ReadOnlyPaths = [ "/etc" ];
      # ReadWritePaths: Allow access to nscd socket for user/group lookups
      # Allow write to "/var/lib/atftp"
      ReadWritePaths = [ "/var/lib/atftp" "/var/run/nscd" ];
      InaccessiblePaths = [ "/proc" "/sys" "/dev" "/boot" "/root" "/home" ];
    };
  };

  # Firewall rules for TFTP are now handled by nftables in firewall.nix

  # Create TFTP directory with appropriate permissions
  system.activationScripts.tftp-dir = ''
    mkdir -p /var/lib/atftp
    chown atftpd:atftpd /var/lib/atftp
    chmod 755 /var/lib/atftp
  '';
}