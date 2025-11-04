#
# nixos/qotom/nfb/services.freeradius.nix
#
# FreeRADIUS server configuration with PAM authentication using Google Authenticator
# This module configures FreeRADIUS to authenticate users via PAM, which uses Google Authenticator
#
# References:
# - https://nixos.wiki/wiki/FreeRADIUS
# - https://freeradius.org/documentation/
# - https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/freeradius.nix
#
# Note: The NixOS FreeRADIUS module only provides basic service setup.
# Configuration files must be written to /etc/raddb manually using environment.etc

{ config, pkgs, lib, ... }:

let
  # Configuration directory for FreeRADIUS
  raddbDir = "/etc/raddb";

  # Default site configuration - define once, use in both places
  # Ultra-minimal configuration for PAM-based authentication
  # Only PAM module - simplest possible configuration
  defaultSiteConfig = ''
    # Default site configuration for FreeRADIUS
    # Uses PAM for authentication with Google Authenticator
    # Minimal configuration - only PAM authentication

    # Listen on authentication port (UDP 1812)
    listen {
      type = auth
      ipaddr = *
      port = 0
    }

    # Listen on accounting port (UDP 1813)
    listen {
      type = acct
      ipaddr = *
      port = 0
    }

    server default {
      # Authorization (user lookup and Auth-Type setting)
      # PAM module can't be used here - need to set Auth-Type
      authorize {
        # Set Auth-Type to PAP for PAM authentication
        update control {
          Auth-Type := PAP
        }
      }

      # Authentication - use PAM here
      authenticate {
        Auth-Type PAP {
          pam
        }
        Auth-Type CHAP {
          pam
        }
        Auth-Type MS-CHAP {
          pam
        }
      }

      # Pre-proxy authorization
      pre-proxy {
      }

      # Post-proxy authorization
      post-proxy {
      }

      # Pre-accounting - prepare accounting records
      preacct {
        # Pre-process accounting packets
      }

      # Accounting - log accounting records for auditing
      # This provides auditing of commands run on routers
      accounting {
        # Write detailed accounting records to file
        detail
        # Write to Unix-style log (wtmp-like)
        unix
        # Write session records
        radutmp
      }

      # Session management - track user sessions
      session {
        radutmp
      }

      # Post-authentication - process after authentication
      post-auth {
        # Reject handling if needed
        Post-Auth-Type REJECT {
          # Filter attributes for reject messages
        }
      }
    }
  '';
in
{
  # Enable FreeRADIUS service
  services.freeradius = {
    enable = true;
    # Use default configDir (/etc/raddb)
    configDir = raddbDir;
    # Override package to be minimal - only PAM support, disable all optional modules
    # This reduces memory usage, attack surface, and build time
    package = (pkgs.freeradius.override {
      withLdap = false;
      withSqlite = false;
      withMysql = false;
      withPostgresql = false;
      withRedis = false;
      withRest = false;
      withJson = false;
      withYubikey = false;
      withMemcached = false;
      withCollectd = false;
    }).overrideAttrs (oldAttrs: {
      buildInputs = (oldAttrs.buildInputs or []) ++ [
        pkgs.linux-pam
      ];
    });
  };

  # Write FreeRADIUS configuration files
  environment.etc = {
    # Clients configuration - defines routers that can authenticate against this server
    "raddb/clients.conf".text = ''
      # FreeRADIUS clients configuration
      # Each router needs a shared secret configured here and on the router

      # Localhost client for testing
      # Note: require_message_authenticator = yes is recommended for BlastRADIUS protection
      # However, radtest from command line may not always include Message-Authenticator
      client localhost {
        ipaddr = 127.0.0.1
        secret = testing123
        require_message_authenticator = yes
        nas_type = other
      }

      # Cisco ASA Firewall (172.16.40.30)
      # Management interface: Management1/1
      client ciscoasa {
        ipaddr = 172.16.40.30
        secret = ASA-RADIUS-Secret-2025-Secure-Key-Please-Change-Me
        require_message_authenticator = yes
        nas_type = cisco
      }

      # Example router clients - uncomment and configure as needed
      # client router1 {
      #   ipaddr = 192.168.1.1
      #   secret = changeme-strong-secret-here
      #   require_message_authenticator = yes
      #   nas_type = other
      # }
      #
      # client router2 {
      #   ipaddr = 192.168.1.2
      #   secret = another-strong-secret
      #   require_message_authenticator = yes
      #   nas_type = other
      # }
    '';

    # Main radiusd.conf - minimal configuration
    # Based on FreeRADIUS package defaults, adapted for NixOS
    "raddb/radiusd.conf".text = ''
      # FreeRADIUS main configuration file
      # Minimal configuration for PAM-based authentication

      # Package paths - use config.services.freeradius.package
      prefix = ${config.services.freeradius.package}
      exec_prefix = ''${prefix}
      sysconfdir = /etc
      localstatedir = /var
      sbindir = ''${prefix}/bin
      logdir = ''${localstatedir}/log/radius
      raddbdir = ${raddbDir}
      radacctdir = ''${logdir}/radacct
      run_dir = ''${localstatedir}/run/radiusd
      db_dir = ''${raddbdir}
      libdir = ''${prefix}/lib

      # Server name
      name = radiusd

      # Config directories
      confdir = ''${raddbdir}
      modconfdir = ''${confdir}/mods-config
      certdir = ''${confdir}/certs
      cadir   = ''${confdir}/certs

      # PID file
      pidfile = ''${run_dir}/''${name}.pid

      # Request handling
      max_request_time = 30
      cleanup_delay = 5
      max_requests = 1024
      hostname_lookups = no

      # Note: user, group, and allow_core_dumps are deprecated in FreeRADIUS 3.2.7
      # They are now handled by systemd service configuration

      # Logging
      log {
        destination = files
        colourise = yes
        file = ''${logdir}/radius.log
        syslog_facility = daemon
        stripped_names = no
        auth = yes              # Enable authentication logging for debugging
        auth_badpass = yes      # Log bad passwords for debugging
        auth_goodpass = yes     # Log good passwords for debugging
        msg_denied = "You are already logged in - access denied"
      }

      # Checkrad program
      checkrad = ''${sbindir}/checkrad

      # Security settings (allow_core_dumps removed - deprecated in 3.2.7)
      security {
        max_attributes = 200
        reject_delay = 1
        status_server = yes
        require_message_authenticator = auto
        limit_proxy_state = auto
      }

      # Proxy requests
      proxy_requests = yes

      # Thread pool
      thread pool {
        start_servers = 5
        max_servers = 32
        min_spare_servers = 3
        max_spare_servers = 10
        max_requests_per_server = 0
        auto_limit_acct = no
      }

      # Modules - include module configurations
      modules {
        $INCLUDE ''${confdir}/mods-enabled/
      }

      # Instantiate modules
      instantiate {
      }

      # Policy
      policy {
      }

      # Include configuration files
      $INCLUDE ''${confdir}/clients.conf
      $INCLUDE ''${confdir}/sites-enabled/
    '';

    # PAM module configuration - write directly to mods-enabled
    # FreeRADIUS loads modules from mods-enabled directory
    "raddb/mods-enabled/pam".text = ''
      # PAM module configuration for FreeRADIUS
      # This uses the radiusd PAM service (defined in security.pam.services.radiusd)
      pam {
        pam_auth = radiusd
      }
    '';

    # Detail module - detailed accounting logs
    "raddb/mods-enabled/detail".text = ''
      # Detailed accounting logging
      # Logs to /var/log/radius/radacct/*/detail-YYYYMMDD files
      # One file per router IP address, one file per day
      detail {
        filename = ''${radacctdir}/%{%{Packet-Src-IP-Address}:-%{Packet-Src-IPv6-Address}}/detail-%Y%m%d
        permissions = 0600
        dirperm = 0755
        locking = no
        log_packet_header = no
        log_request_authenticator = no
      }
    '';

    # Unix module - Unix-style accounting (like wtmp)
    "raddb/mods-enabled/unix".text = ''
      # Unix-style accounting (wtmp-like logs)
      unix {
        radwtmp = ''${logdir}/radwtmp
      }
    '';

    # Radutmp module - session tracking
    "raddb/mods-enabled/radutmp".text = ''
      # Session tracking for accounting
      radutmp {
        filename = ''${run_dir}/radutmp
        username = %{User-Name}
        case_sensitive = yes
        check_with_nas = yes
        permissions = 0600
        caller_id = yes
      }
    '';

    # Site configuration - available version (for reference)
    "raddb/sites-available/default".text = defaultSiteConfig;

    # Enable default site - write directly to sites-enabled
    # FreeRADIUS loads sites from sites-enabled directory
    "raddb/sites-enabled/default".text = defaultSiteConfig;
  };

  # Configure PAM for FreeRADIUS (radiusd service)
  # This PAM service will use Google Authenticator for TOTP validation
  security.pam.services.radiusd = {
    # Enable Google Authenticator for RADIUS authentication
    googleAuthenticator = {
      enable = true;
      # Allow users without TOTP configured (set to false to require TOTP)
      # nullOk = false;
    };
  };

  # Create necessary directories for FreeRADIUS before service starts
  # systemd needs these directories to exist before bind-mounting them in the namespace
  systemd.tmpfiles.rules = [
    # Create log directory
    "d /var/log/radius 0750 radius radius -"
    # Create accounting directory
    "d /var/log/radius/radacct 0750 radius radius -"
    # Create runtime directory
    "d /var/run/radiusd 0750 radius radius -"
  ];

  # Security hardening for FreeRADIUS service
  # systemd-analyze security freeradius.service
  # Target: Reduce exposure level from 8.7 to ≤ 3.0
  # Note: Default service only sets: User, ProtectSystem, ProtectHome, Restart, RestartSec, LogsDirectory
  # Only use lib.mkForce for attributes already set by the default service
  systemd.services.freeradius = {
    serviceConfig = {
      # User/Group already set by services.freeradius (radius:radius)

      # Resource limits (not set by default service, so no mkForce needed)
      MemoryMax = "150M";
      MemoryHigh = "120M";
      CPUQuota = "100%";
      LimitNOFILE = 1024;
      LimitNPROC = 200;

      # Security restrictions - process isolation (not set by default, so no mkForce)
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
      ProtectProc = "invisible";
      ProcSubset = "pid";

      # Additional security restrictions (not set by default, so no mkForce)
      NoNewPrivileges = true;
      RestrictSUIDSGID = true;
      PrivateTmp = true;
      PrivateUsers = false;  # Must be false: FreeRADIUS needs access to /etc/passwd and /etc/group for PAM user lookups
      RemoveIPC = true;

      # System call architecture restriction (not set by default, so no mkForce)
      SystemCallArchitectures = "x86-64";

      # System call filtering (not set by default, so no mkForce)
      # Note: Excluding @privileged or @resources causes FreeRADIUS/PAM to crash
      # PAM authentication requires various system calls that are part of these groups
      # We keep @system-service which includes necessary calls for network and file operations
      SystemCallFilter = [
        "@system-service"
        "~@mount"
        "~@debug"
        "~@module"
        "~@reboot"
        "~@swap"
        "~@obsolete"
      ];

      # Restrict address families (not set by default, so no mkForce)
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];

      # Device access (minimal)
      # /dev/null: rw for stdout/stderr redirection
      # /dev/zero: r only (read zeros for memory initialization, no need to write)
      # /dev/urandom and /dev/random: r only for random number generation
      DeviceAllow = [
        "/dev/null rw"
        "/dev/zero r"
        "/dev/urandom r"
        "/dev/random r"
      ];

      # Capabilities (not set by default, so no mkForce)
      CapabilityBoundingSet = [ ];
      AmbientCapabilities = [ ];

      # File permissions (not set by default, so no mkForce)
      UMask = "0077";

      # File system restrictions
      # ProtectSystem and ProtectHome are already set by default service, so use mkForce
      ProtectSystem = lib.mkForce "full";
      ProtectHome = lib.mkForce true;

      # ReadOnlyPaths: Configuration, system files, and Nix store needed for operation
      # /etc/raddb: FreeRADIUS configuration
      # /etc: Required for PAM user/group lookups (passwd, group, nsswitch.conf, etc.)
      # /nix: Required for accessing Nix store executables and scripts
      ReadOnlyPaths = [ "/etc/raddb" "/etc" "/nix" ];

      # ReadWritePaths: Logs, runtime, and accounting directories
      # /var/log/radius: Main log directory
      # /var/log/radius/radacct: Accounting records (one subdirectory per router IP)
      # /var/run/radiusd: Runtime files (PID, radutmp, etc.)
      # /var/run/nscd: Name service cache daemon socket (for user lookups)
      ReadWritePaths = [
        "/var/log/radius"
        "/var/log/radius/radacct"
        "/var/run/radiusd"
        "/var/run/nscd"
      ];

      # InaccessiblePaths: Block access to unnecessary paths
      # Note: /nix is in ReadOnlyPaths for script execution
      # Note: /dev is controlled via DeviceAllow, so don't put it in InaccessiblePaths
      InaccessiblePaths = [ "/proc" "/sys" "/boot" "/root" "/home" ];
    };
  };

  # Open firewall ports for FreeRADIUS
  # UDP 1812: Authentication
  # UDP 1813: Accounting
  networking.firewall.allowedUDPPorts = [ 1812 1813 ];

  # Ensure required packages are available
  environment.systemPackages = with pkgs; [
    freeradius  # Includes radtest for testing
    google-authenticator  # For user enrollment
    oath-toolkit  # CLI tools for token management
  ];
}

