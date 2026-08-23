#
# nixos/hp/hp4/smokeping.nix
#

# Smokeping is a little redundant with blackbox.nix, but it's a good way to
# have a web interface to the data.  Smokeping has it's own database, so if there is ever
# a problem with the blackbox exporter, we can still have a web interface to the data.

# https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/smokeping.nix
# https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/exporters/smokeping.nix

# https://oss.oetiker.ch/smokeping/doc/smokeping_examples.en.html
# https://oss.oetiker.ch/smokeping/probe/Curl.en.html
# https://oss.oetiker.ch/smokeping/probe/DNS.en.html

{ config, lib, pkgs, ... }:

let
  # Shared, single-source-of-truth device/host list (IPv4 + IPv6), ALSO consumed by
  # blackbox.nix + prometheus.nix — so the smokeping and blackbox monitoring paths
  # can never drift again (that drift is why blackbox had gone stale). Add or change a
  # device once in network-targets.nix and both paths pick it up. v6pfx lives there too.
  nt = import ./network-targets.nix { inherit lib; };

  # Smokeping targets = the shared ICMP categories (DNS servers, internet, network
  # devices, access points) + smokeping's own HTTP (Curl) and DNS-lookup probes,
  # whose probe syntax is smokeping-specific and stays here.
  targets = nt.categories // {

    # HTTP connection-SETUP timing (cold TCP+TLS handshake).
    #
    # NOTE: Smokeping's Curl probe forks a fresh `curl` for every ping, so it always opens
    # a NEW TCP+TLS connection and measures the ~2-3 round-trip + crypto SETUP cost (~50ms
    # to a ~10ms-away edge). It is NOT page latency - a warm request to these edges is
    # ~10-25ms. Real warm/persistent HTTP latency (v4+v6) lives in Grafana:
    # "HTTP Latency - Persistent vs Cold (v4/v6)" (uid http-persistent). Keep this section
    # as a fresh-connection reachability + TLS-handshake health check, honestly labelled.
    "HTTP" = {
      title = "HTTP Connection Setup - cold TCP+TLS handshake (NOT page latency; see Grafana http-persistent)";
      menu = "HTTP Setup (cold)";
      targets = {
        "Google_HTTP" = {
          name = "Google - cold connection setup (TCP+TLS)";
          host = "google.com";
          probe = "Curl";
        };
        "IBM_HTTP" = {
          name = "IBM - cold connection setup (TCP+TLS)";
          host = "ibm.com";
          probe = "Curl";
        };
        "Yahoo_HTTP" = {
          name = "Yahoo - cold connection setup (TCP+TLS)";
          host = "yahoo.com";
          probe = "Curl";
        };
        "Facebook_HTTP" = {
          name = "Facebook - cold connection setup (TCP+TLS)";
          host = "facebook.com";
          probe = "Curl";
        };
      };
    };

    # Add DNS lookup testing
    "DNSLookup" = {
      title = "DNS Resolution Testing (dig queries)";
      menu = "DNS Resolution";
      targets = {
        "Google_DNS_Lookup" = {
          name = "Google DNS IPv4 - google.com lookup";
          host = "8.8.8.8";
          probe = "DNS";
          lookup = "google.com";
        };
        "Google_DNS_Lookup_IPv6" = {
          name = "Google DNS IPv6 - google.com lookup";
          host = "2001:4860:4860::8888";
          probe = "DNS";
          lookup = "google.com";
        };
        "Cloudflare_DNS_Lookup" = {
          name = "Cloudflare DNS IPv4 - google.com lookup";
          host = "1.1.1.1";
          probe = "DNS";
          lookup = "google.com";
        };
        "Cloudflare_DNS_Lookup_IPv6" = {
          name = "Cloudflare DNS IPv6 - google.com lookup";
          host = "2606:4700:4700::1111";
          probe = "DNS";
          lookup = "google.com";
        };
        "Local_DNS_Lookup" = {
          name = "Local DNS - google.com lookup";
          host = "::1";
          probe = "DNS";
          lookup = "google.com";
        };
      };
    };
  };

  # Helper function to generate smokeping target configuration
  generateTargetConfig = categoryName: category: ''
+ ${categoryName}
menu = ${category.menu}
title = ${category.title}

${lib.concatStringsSep "\n" (lib.mapAttrsToList (targetName: target: ''
++ ${targetName}
menu = ${target.name}
title = ${target.name}${lib.optionalString (target ? probe) "\nprobe = ${target.probe}"}
host = ${target.host}${lib.optionalString (target ? lookup) "\nlookup = ${target.lookup}"}
'' ) category.targets)}'';

  # Generate the complete target configuration
  targetConfig = ''
probe = FPing

menu = Top
title = Network Latency Grapher
remark = Welcome to the SmokePing website of Siden Network Operations. \
         Here you will learn all about the latency of our network.

${lib.concatStringsSep "\n" (lib.mapAttrsToList generateTargetConfig targets)}'';

  # Generate prometheus targets from the same data structure
  prometheusTargets = lib.flatten (lib.mapAttrsToList (categoryName: category:
    lib.mapAttrsToList (targetName: target:
      {
        name = "${categoryName}_${targetName}";
        host = target.host;
      }) category.targets
  ) targets);

in {
  # Smokeping configuration for network monitoring
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/smokeping.nix
  services.smokeping = {
    enable = true;
    webService = false;  # Disable automatic nginx configuration to avoid conflicts

    # Basic configuration
    owner = "Network Operations";
    ownerEmail = "ops@siden.io";
    hostName = "smokeping.localhost";

    # Database configuration (5 minute intervals, 20 pings per step)
    # Using AVERAGE as the consolidation function (MEDIAN is not supported)
    databaseConfig = ''
      step     = 300
      pings    = 20
      # consfn mrhb steps total
      AVERAGE  0.5   1  1008
      AVERAGE  0.5  12  4320
          MIN  0.5  12  4320
          MAX  0.5  12  4320
      AVERAGE  0.5 144   720
          MAX  0.5 144   720
          MIN  0.5 144   720
    '';

    # Probe configuration for both IPv4 and IPv6
    # Modern fping handles IPv6 addresses automatically
    probeConfig = ''
      + FPing
      binary = ${config.security.wrapperDir}/fping

      # https://oss.oetiker.ch/smokeping/probe/Curl.en.html
      + Curl
      binary = ${pkgs.curl}/bin/curl
      urlformat = https://%host%/robots.txt
      timeout = 9
      step = 300
      follow_redirects = yes
      include_redirects = no
      agent = User-Agent: smokeping-curl
      extraargs = --silent --compressed --http2
      #extraargs = --silent
      #extraargs = --silent --show-error --fail --location --max-redirs 3 --connect-timeout 2 --max-time 8 --output /dev/null --compressed --http2 --user-agent=smokeping-curl
      #extraargs = --silent --show-error --fail --location --max-redirs 3 --connect-timeout 2 --max-time 8 --output /dev/null --compressed --http2 --user-agent=smokeping-curl

      + DNS
      binary = ${pkgs.bind.dnsutils}/bin/dig
      timeout = 15
      step = 300
    '';

    # Target configuration generated from data structure
    inherit targetConfig;

    # Alert configuration
    alertConfig = ''
      to = root@localhost
      from = smokeping@localhost

      +someloss
      type = loss
      pattern = >0%,*12*,>0%,*12*,>0%
      comment = Loss of connectivity

      +highloss
      type = loss
      pattern = >50%,*12*,>50%,*12*,>50%
      comment = High loss of connectivity

      +highlatency
      type = rtt
      pattern = >100,*12*,>100,*12*,>100
      comment = High latency detected
    '';

    # Presentation configuration
    presentationConfig = ''
      + charts
      menu = Charts
      title = The most interesting destinations
      ++ stddev
      sorter = StdDev(entries=>4)
      title = Top Standard Deviation
      menu = Std Deviation
      format = Standard Deviation %f
      ++ max
      sorter = Max(entries=>5)
      title = Top Max Roundtrip Time
      menu = by Max
      format = Max Roundtrip Time %f seconds
      ++ loss
      sorter = Loss(entries=>5)
      title = Top Packet Loss
      menu = Loss
      format = Packets Lost %f
      ++ median
      sorter = Median(entries=>5)
      title = Top Median Roundtrip Time
      menu = by Median
      format = Median RTT %f seconds
      + overview
      width = 600
      height = 50
      range = 10h
      + detail
      width = 600
      height = 200
      unison_tolerance = 2
      "Last 3 Hours"    3h
      "Last 30 Hours"   30h
      "Last 10 Days"    10d
      "Last 360 Days"   360d
    '';
  };

  # Prometheus smokeping prober - DISABLED: redundant with main smokeping service
  # services.prometheus.exporters.smokeping = {
  #   enable = true;
  #   port = 9374;
  #   pingInterval = "300s";  # 5 minutes to match smokeping
  #   hosts = lib.flatten (lib.mapAttrsToList (categoryName: category:
  #     lib.mapAttrsToList (targetName: target:
  #       target.host
  #     ) category.targets
  #   ) targets);
  # };

  # Firewall rules for web interface
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Ensure nginx can read cache/data for static file serving
  users.users.nginx.extraGroups = [ "smokeping" ];

  systemd.tmpfiles.rules = [
    # ... existing rules ...
    "d /var/lib/smokeping/cache 0750 smokeping smokeping"
    "d /var/lib/smokeping/data 0750 smokeping smokeping"
    "Z /var/lib/smokeping 0750 smokeping smokeping"
  ];

  # Systemd security measures for smokeping
  systemd.slices.smokeping = {
    description = "Smokeping network monitoring slice";
    sliceConfig = {
      MemoryHigh = "200M";
      MemoryMax = "300M";
      # The Curl probe forks ~80 short-lived curl+TLS processes per 300s cycle
      # (HTTP targets x 20 pings). TLS handshakes are CPU-bound and bursty at the
      # top of each cycle. A 20% cap stretched each ~90ms fetch to ~900ms, which
      # showed up as a bogus ~1s "HTTP latency". Smokeping's *average* CPU use is
      # tiny; give the burst 2 cores of headroom so timings reflect the network.
      CPUQuota = "200%";
      TasksMax = 200;
    };
  };

  # Enhanced smokeping service configuration with security measures
  # systemd-analyze security smokeping
  systemd.services.smokeping = {
    serviceConfig = {
      # Resource limits
      Slice = "smokeping.slice";
      MemoryHigh = "200M";
      MemoryMax = "300M";
      # Match the slice: 20% throttled the Curl probe's bursty TLS handshakes and
      # inflated HTTP timings ~10x (bogus ~1s). See the slice comment above.
      CPUQuota = "200%";
      TasksMax = 200;

      # Process limits
      LimitNOFILE = 1024;
      LimitNPROC = 100;

      # Security restrictions
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      PrivateDevices = true;
      RestrictRealtime = true;
      # RestrictSUIDSGID = true;  # Disabled - smokeping needs SUID wrapper for ping
      RestrictNamespaces = true;
      LockPersonality = true;
      # MemoryDenyWriteExecute = true;  # Disabled - interferes with DNS resolution
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];

      # Additional security restrictions
      RemoveIPC = true;  # Clean up IPC objects
      UMask = "0077";  # Restrict file permissions
      SystemCallFilter = [ "@system-service" "~@privileged" "~@mount" "~@debug" "~@module" "~@reboot" "~@swap" "~@clock" "~@cpu-emulation" "~@obsolete" ];  # Allow raw-io for IPv6 ping
      CapabilityBoundingSet = [ "CAP_NET_RAW" "CAP_NET_BIND_SERVICE" ];  # Only network capabilities needed
      ProtectProc = "default";  # Allow access to process info for DNS resolution
      ProcSubset = "all";  # Allow access to all process info
      ProtectHostname = true;  # Prevent hostname changes
      ProtectClock = true;  # Prevent clock changes

      # File system restrictions - allow access to dig
      ReadWritePaths = [
        "/var/lib/smokeping"
        "/var/log"
        "/run"
      ];
      ReadOnlyPaths = [
        "/etc/smokeping.conf"
        "/nix/store"
        "${pkgs.curl}"
        "${config.services.smokeping.package}"
        "${config.security.wrapperDir}"
        "/etc/resolv.conf"
        "/etc/hosts"
        "/etc/nsswitch.conf"
        "/etc/ssl"
        "/etc/ca-bundle.crt"
        "/etc/ssl/certs"
      ];

      # User/group restrictions
      User = "smokeping";
      Group = "smokeping";
      SupplementaryGroups = [ "smokeping" ];

      # Restart policy
      Restart = "on-failure";
      RestartSec = "10s";

      # Nice priority (lower number = higher priority)
      Nice = 10;

      # Required by smokeping module
      ExecStart = "${config.services.smokeping.package}/bin/smokeping --config=/etc/smokeping.conf --nodaemon";
    };

    # Add curl package to the service environment
    path = [ pkgs.curl pkgs.bind.dnsutils ];
    environment = {
      # Ensure DNS resolution works
      NSS_WRAPPER_PASSWD = "/etc/passwd";
      NSS_WRAPPER_GROUP = "/etc/group";
      LD_LIBRARY_PATH = "${pkgs.curl}/lib";
    };
  };

  # Also secure the prometheus smokeping exporter - DISABLED
  # systemd.services.prometheus-smokeping-exporter = {
  #   serviceConfig = {
  #     # Resource limits
  #     MemoryHigh = "512M";
  #     MemoryMax = "1G";
  #     CPUQuota = "25%";
  #
  #     # Security restrictions
  #     NoNewPrivileges = true;
  #     ProtectSystem = "strict";
  #     ProtectHome = true;
  #     ProtectKernelTunables = true;
  #     ProtectKernelModules = true;
  #     ProtectControlGroups = true;
  #     ProtectKernelLogs = true;
  #     PrivateDevices = true;
  #     RestrictRealtime = true;
  #     RestrictSUIDSGID = true;
  #     RestrictNamespaces = true;
  #     LockPersonality = true;
  #     MemoryDenyWriteExecute = true;
  #     RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
  #
  #     # Additional security restrictions
  #     RemoveIPC = true;  # Clean up IPC objects
  #     UMask = "0077";  # Restrict file permissions
  #     SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" "~@mount" "~@debug" "~@module" "~@reboot" "~@swap" "~@clock" "~@cpu-emulation" "~@obsolete" "~@raw-io" ];
  #     CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];  # Only binding capability needed
  #     ProtectProc = "invisible";  # Hide other processes
  #     ProcSubset = "pid";  # Only show own process info
  #     ProtectHostname = true;  # Prevent hostname changes
  #     ProtectClock = true;  # Prevent clock changes
  #
  #     # File system restrictions
  #     ReadWritePaths = [
  #       "/var/log"
  #       "/run"
  #     ];
  #     ReadOnlyPaths = [
  #       "/nix/store"
  #     ];
  #
  #     # Restart policy
  #     Restart = "on-failure";
  #     RestartSec = "10s";
  #
  #     # Nice priority
  #     Nice = 15;
  #   };
  # };
}

# Available Probes in NixOS Smokeping 2.8.2:
#
# Network/Connectivity Probes:
# - FPing: Standard ping using fping binary (IPv4/IPv6)
# - FPing6: Legacy IPv6 ping (deprecated, use FPing)
# - FPingContinuous: Continuous ping monitoring
# - RemoteFPing: Ping through remote host
# - TCPPing: TCP connection testing
# - TraceroutePing: Traceroute-based ping
#
# HTTP/Web Probes:
# - Curl: HTTP/HTTPS testing using curl binary
# - EchoPingHttp: HTTP echo ping
# - EchoPingHttps: HTTPS echo ping
# - WebProxyFilter: Web proxy testing
#
# DNS Probes:
# - DNS: DNS query testing
# - AnotherDNS: Alternative DNS testing
# - EchoPingDNS: DNS echo ping
# - CiscoRTTMonDNS: Cisco DNS monitoring
#
# SSH/Telnet Probes:
# - SSH: SSH connection testing
# - AnotherSSH: Alternative SSH testing
# - TelnetIOSPing: Cisco IOS telnet ping
# - TelnetJunOSPing: Juniper telnet ping
# - OpenSSHEOSPing: OpenSSH to Cisco IOS
# - OpenSSHJunOSPing: OpenSSH to Juniper
#
# Application Probes:
# - LDAP: LDAP connection testing
# - EchoPingLDAP: LDAP echo ping
# - Radius: RADIUS authentication testing
# - TacacsPlus: TACACS+ authentication testing
# - FTPtransfer: FTP file transfer testing
# - NFSping: NFS mount testing
# - Qstat: Quake server status
# - SipSak: SIP protocol testing
#
# Network Equipment Probes:
# - CiscoRTTMonEchoICMP: Cisco ICMP echo monitoring
# - CiscoRTTMonTcpConnect: Cisco TCP connection monitoring
# - DismanPing: DISMAN-PING-MIB SNMP ping
# - IOSPing: Cisco IOS ping
# - IRTT: In-band Round Trip Time
#
# Email Probes:
# - EchoPingSmtp: SMTP echo ping
# - SendEmail: Email sending test
#
# Other Probes:
# - EchoPingChargen: Chargen echo ping
# - EchoPingDiscard: Discard echo ping
# - EchoPingIcp: ICP echo ping
# - EchoPingWhois: Whois echo ping
# - EchoPingPlugin: Plugin-based echo ping
# - passwordchecker: Password checking
#
# Note: The HTTP probe is NOT available in NixOS smokeping 2.8.2.
# Use Curl probe for HTTP/HTTPS testing instead.