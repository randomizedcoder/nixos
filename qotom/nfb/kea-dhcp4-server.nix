# Kea DHCP4 Server Configuration
# Migration from legacy dhcpd to Kea DHCP4 server
# This configuration replicates the functionality of dhcpd.conf and ipxe-metal.conf

# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/kea.nix
# https://github.com/isc-projects/kea/tree/master/doc/examples/kea4

# ipxe example
# https://github.com/ipxe/ipxe/discussions/884

{ config, lib, pkgs, ... }:

let
  # Import centralized network data
  networkData = import ./network-data.nix;

  # Get the management interface name
  mgmtInterfaceName = lib.head (lib.attrNames networkData.mgmtInterface);

  # Helper function to get the first 3 octets of an IP address
  getFirstThreeOctets = ip:
    let
      # Split by "/" to remove subnet mask, then split by "." to get octets
      ipPart = lib.head (lib.splitString "/" ip);
      octets = lib.splitString "." ipPart;
    in
    # Take first 3 octets and join them back together
    lib.concatStringsSep "." (lib.take 3 octets);

  # Helper function to check if an interface IP matches a subnet
  interfaceMatchesSubnet = interfaceIp: subnet:
    let
      interfacePrefix = getFirstThreeOctets interfaceIp;
      subnetPrefix = getFirstThreeOctets subnet;
    in
    interfacePrefix == subnetPrefix;

  # Define the subnets that Kea will serve
  keaSubnets = [
    "192.168.99.0/24"
    "192.168.100.0/24"
  ];

  # Helper function to check if an interface should listen based on its node0 IP
  interfaceShouldListen = interfaceConfig:
    let
      # Only check node0 since all IPs on an interface share the same subnet
      node0Ip = interfaceConfig.node0 or null;
      hasMatchingSubnet = node0Ip != null &&
        lib.any (subnet: interfaceMatchesSubnet node0Ip subnet) keaSubnets;
    in
    hasMatchingSubnet;

  # Build list of interfaces to listen on by checking which interfaces
  # have IP addresses that match our subnet definitions
  dhcpInterfaces =
    let
      # Get all interfaces from network data
      allInterfaces =
        # Management interface
        [ { name = mgmtInterfaceName; config = networkData.mgmtInterface.${mgmtInterfaceName}; } ]
        # VLAN interfaces - use the actual interface name from config
        ++ (lib.mapAttrsToList (name: config: {
          name = config.name;  # Use the actual interface name from config
          config = config;
        }) networkData.vlanConfigs);

      # Filter interfaces that have node0 IPs matching our subnets
      matchingInterfaces = lib.filter (interface:
        interfaceShouldListen interface.config
      ) allInterfaces;
    in
    map (interface: interface.name) matchingInterfaces;

  # Helper function to create host reservations
  createHostReservation = hostname: mac: ip: {
    hw-address = mac;
    ip-address = ip;
    hostname = hostname;
  };

  # Fixed host reservations from dhcpd.conf
  fixedHosts = [
    (createHostReservation "c0e02na" "3c:ec:ef:10:10:92" "192.168.99.50")
    (createHostReservation "c0e02nb" "a0:36:9f:94:27:1f" "192.168.99.51")
    (createHostReservation "c0e14n" "3c:ec:ef:02:b2:13" "192.168.99.14")
    (createHostReservation "c0e15n" "3c:ec:ef:02:b3:33" "192.168.99.15")
    (createHostReservation "c0e16n" "3c:ec:ef:04:2e:95" "192.168.99.16")
    (createHostReservation "c0e17n" "24:6e:96:56:84:9c" "192.168.99.17")
    (createHostReservation "c0e19n" "24:6e:96:54:8b:ec" "192.168.99.19")
    (createHostReservation "c0e28n" "24:6e:96:47:19:84" "192.168.99.28")
    (createHostReservation "c0e30n" "24:6e:96:47:1b:3c" "192.168.99.30")
    (createHostReservation "c0e32n" "24:6e:96:67:0b:a4" "192.168.99.32")
    (createHostReservation "c0e34n" "24:6e:96:47:26:a4" "192.168.99.34")
    (createHostReservation "c0e36n" "24:6e:96:56:89:8c" "192.168.99.36")
    (createHostReservation "c0e38n" "24:6e:96:56:27:d4" "192.168.99.38")
  ];

in {
  # Enable Kea DHCP4 server
  # systemctl status kea-dhcp4-server.service
  services.kea.dhcp4 = {
    enable = true;

    # Kea DHCP4 server configuration
    settings = {
      # Global configuration
      valid-lifetime = 302400;  # 3.5 days (half of 7 days) - default: 43200 (12 hours)
      max-valid-lifetime = 604800;  # 7 days - default: 86400 (24 hours)

      # DNS servers (global fallback)
      option-data = [
        {
          name = "domain-name-servers";
          data = "1.1.1.1, 8.8.8.8";
        }
        {
          name = "ntp-servers";
          data = "192.168.99.254, 192.168.100.254";
        }
      ];

      # Client classes for PXE/iPXE boot configuration (global level)
      client-classes = [
        {
          name = "ipxeclient";
          test = "option[77].hex == 'iPXE'";
          boot-file-name = "http://169.254.254.210:8081/boot.ipxe";
          next-server = "169.254.254.210";
        }
        # Legacy BIOS PXE clients
        {
          name = "biosclients";
          test = "not member('ipxeclient') and option[93].hex == 0x0000";
          boot-file-name = "undionly.kpxe";
          next-server = "192.168.99.210";
        }
        # UEFI PXE clients
        {
          name = "pxeclients";
          test = "not member('ipxeclient') and not member('biosclients')";
          boot-file-name = "snp.efi";
          next-server = "192.168.99.210";
        }
        # UEFI HTTP clients
        {
          name = "httpclients";
          test = "not member('ipxeclient') and option[60].text == 'HTTPClient'";
          boot-file-name = "http://192.168.99.210:8081/tftp/snp.efi";
          next-server = "192.168.99.210";
        }
      ];

      # Subnet configurations - using correct subnet4 syntax
      subnet4 = [
        {
          # Subnet 192.168.99.0/24 (equivalent to dhcpd subnet)
          id = 1;
          subnet = "192.168.99.0/24";
          pools = [
            {
              pool = "192.168.99.50 - 192.168.99.150";
            }
          ];
          option-data = [
            {
              name = "routers";
              data = "192.168.99.254";
            }
            {
              name = "domain-name-servers";
              data = "192.168.99.254, 1.1.1.1, 8.8.8.8";
            }
            {
              name = "ntp-servers";
              data = "192.168.99.254";
            }
          ];

          # Fixed host reservations
          reservations = fixedHosts;
        }
        {
          # Subnet 192.168.100.0/24 (equivalent to dhcpd subnet)
          id = 2;
          subnet = "192.168.100.0/24";
          pools = [
            {
              pool = "192.168.100.50 - 192.168.100.200";
            }
          ];
          option-data = [
            {
              name = "routers";
              data = "192.168.100.254";
            }
            {
              name = "domain-name-servers";
              data = "192.168.100.254, 1.1.1.1, 8.8.8.8";
            }
            {
              name = "ntp-servers";
              data = "192.168.100.254";
            }
          ];
        }
      ];

      # Interfaces to listen on - dynamically built from network data
      # Only interfaces with IPs matching our subnet definitions
      interfaces-config = {
        interfaces = dhcpInterfaces;
        dhcp-socket-type = "raw";
      };

      # Lease database configuration
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/kea-leases4.csv";
        lfc-interval = 3600;
      };



      # Control socket for management
      control-socket = {
        socket-type = "unix";
        socket-name = "/var/run/kea/kea4-ctrl-socket";
      };

      # DHCPv4 specific options
      dhcp4o6-port = 0;  # Disable DHCPv4-over-DHCPv6

      # Echo client-id option (for compatibility)
      echo-client-id = true;

      # Match client-id option (for compatibility)
      match-client-id = true;

      # Authoritative server
      authoritative = true;

      # Boot file name option
      boot-file-name = "";

      # Next server option
      next-server = "";
    };
  };

  # Security hardening for Kea DHCP4 service
  # systemd-analyze security kea-dhcp4-server.service
  systemd.services.kea-dhcp4-server = {
    # Resource limits
    serviceConfig = {
      # Memory limits
      MemoryMax = "100M";
      MemoryHigh = "80M";

      # CPU limits
      CPUQuota = "20%";

      # Process limits
      LimitNOFILE = 256;
      LimitNPROC = 100;

      # Additional security restrictions not already set by Kea
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

      # System call filtering (less restrictive for DHCP functionality)
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
        "~@mount"
        "~@debug"
        "~@module"
        "~@reboot"
        "~@swap"
        "~@obsolete"
        "~@cpu-emulation"
        "~@clock"
        # Allow additional system calls for kea-lfc process
        "sched_getaffinity"
        "sched_setaffinity"
        "sched_yield"
        "getcpu"
        "getpriority"
        "setpriority"
        "nice"
        "sched_getparam"
        "sched_setparam"
        "sched_getscheduler"
        "sched_setscheduler"
        "sched_get_priority_max"
        "sched_get_priority_min"
        "sched_rr_get_interval"
      ];

      # Restrict address families (allow raw sockets for DHCP)
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" "AF_PACKET" ];

      # Device access (minimal)
      DeviceAllow = [
        "/dev/null rw"
        "/dev/zero rw"
        "/dev/urandom r"
        "/dev/random r"
      ];

      # Additional restrictions that should be safe for DHCP
      PrivateDevices = true;
      ProtectHome = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
    };
  };

  # Firewall rules for DHCP
  networking.firewall.allowedUDPPorts = [ 67 68 ];
}