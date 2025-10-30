#
# https://gitlab.com/sidenio/nix/data_center/lax/dcops0_hp2/network.nix
#
# VLAN CONFIGURATION NOTES:
# ========================
#
# IMPORTANT: VLAN configuration in systemd-networkd has specific requirements:
#
# 1. VLAN Configuration Method:
#    - VLANs are configured using the 'vlan' attribute in the parent interface's network config
#    - The parent interface (bond0) must specify which VLANs to create using: vlan = [ "vlan.20" "vlan.30" "vlan.50" "vlan.100" ]
#    - Each VLAN also needs its own netdev configuration and network configuration
#
# 2. Systemd Limitations (CRITICAL):
#    - systemd.network.netdevs only applies when netdevs are FIRST CREATED
#    - Existing netdevs (like VLAN interfaces) will NOT be modified by configuration changes
#    - If VLAN interfaces exist from previous configurations, they must be manually removed first
#    - Reference: https://github.com/systemd/systemd/issues/9627
#    - See also: https://www.man7.org/linux/man-pages/man5/systemd.network.5.html
#
# 3. Troubleshooting VLAN Issues:
#    - Check for existing VLAN interfaces: ip link show | grep vlan
#    - Remove existing VLANs if they exist: sudo ip link delete vlan.20 (repeat for each VLAN)
#    - Rebuild configuration: sudo nixos-rebuild switch
#    - Check systemd-networkd logs: sudo journalctl -u systemd-networkd -f
#
# 4. VLAN Configuration Structure:
#    - vlanConfigs: Defines VLAN parameters (name, id, address, parent)
#    - createVlanNetdev: Creates netdev configuration for each VLAN
#    - createVlanNetwork: Creates network configuration for each VLAN
#    - vlanNames: Extracts VLAN names for the parent interface's vlan attribute
#
# 5. Example from NixOS Wiki:
#    https://nixos.wiki/wiki/Systemd-networkd#VLAN
#    networks = {
#      "30-enp1s0" = {
#        matchConfig.Name = "enp1s0";
#        vlan = [ "vlan10" "vlan20" ];  # This creates the VLANs on the parent
#      };
#    };
#
# MTU CONFIGURATION NOTES:
# =======================
#
# CRITICAL: Bond interface MTU behavior (VERY IMPORTANT):
# - Bond interfaces inherit MTU from their slave interfaces
# - Bond interface MTU CANNOT be higher than the lowest MTU of any slave interface
# - If you try to set bond0 MTU to 9216 but slaves have MTU 9212, you'll get "Invalid argument" error
# - All interfaces in the chain must have consistent MTU: Physical → Bond → VLANs
# - Current configuration uses MTU 9212 for all interfaces (jumbo frames)
#
# HARDWARE/DRIVER LIMITATIONS:
# - This system uses Intel e1000e driver (enp4s0f0, enp4s0f1)
# - e1000e driver supports maximum MTU of ~9212 bytes for jumbo frames
# - This is why we use MTU 9212 instead of 9216 (full jumbo frame size)
# - Check driver: sudo ethtool --driver enp4s0f0
# - Different network cards/drivers may support different MTU limits
#
# MTU Hierarchy:
# - Physical interfaces (enp4s0f0, enp4s0f1): MTU 9212 (e1000e driver limit)
# - Bond interface (bond0): MTU 9212 (inherits from slaves, can't be higher)
# - VLAN interfaces (vlan.20, vlan.30, vlan.100): MTU 9212 (consistent with bond)
# - Management interface (eno1): MTU 9212 (consistent)
#
# Troubleshooting MTU Issues:
# - Check current MTU: ip link show
# - Check driver limitations: sudo ethtool --driver <interface>
# - Try setting MTU manually: sudo ip link set bond0 mtu 9212
# - If you get "Invalid argument", check slave interface MTUs first
# - Remove and recreate interfaces if MTU changes don't take effect
#
# WIREGUARD CONFIGURATION NOTES:
# =============================
#
# Multi-Interface WireGuard Setup:
# - Legacy wg0 interface: Uses 169.254.254.101/32 with 1000M cake policy
# - wg-engineers: Uses 172.16.40.1/24 with 100M cake policy
# - wg-mtn: Uses 172.16.41.1/24 with 200M cake policy
# - wg-ccl-mgmt: Uses 172.16.42.1/24 with 20M cake policy
# - wg-emergency: Uses 172.16.43.1/24 with pfifo_fast (no shaping)
#
# QoS Policies:
# - Each WireGuard interface has its own cake policy for traffic shaping
# - Emergency interface uses pfifo_fast for maximum throughput
# - All interfaces use consistent MTU and overhead settings
#
# ACTIVE/STANDBY CONFIGURATION NOTES:
# ===================================
#
# This configuration supports active/standby pairs:
# - thisNode: Set to "node0" for primary node, "node1" for standby node
# - bondConfig: Contains node0 and node1 addresses for bond interface
# - vlanConfigs: Contains node0 and node1 addresses for each VLAN
# - IP selection: Automatically selects correct IP based on thisNode value
#
# Please read the wireguard.nix file for the WireGuard configuration

{ config, lib, pkgs, thisNode, ... }:

let
  # Import centralized network data
  networkData = import ./network-data.nix;

  # thisNode is passed from flake.nix configuration

  testMgmtInterface = networkData.testMgmtInterface;
  mgmtInterface = networkData.mgmtInterface;
  bondConfig = networkData.bondConfig;
  vlanConfigs = networkData.vlanConfigs;
  cakeConfig = networkData.cakeConfig;
  MTUBytes = networkData.MTUBytes;

  # Import WireGuard data for interface configurations
  wireguardData = import ./wireguard-data.nix;
  wireguardInterfaces = wireguardData.wireguardInterfaces;

  # Helper function to get the correct IP address based on thisNode
  getNodeAddress = config: config.${thisNode};

  # Helper function to extract IP address from CIDR notation
  extractIP = cidr: lib.head (lib.splitString "/" cidr);

  # Helper function to construct full IP address from subnet base and suffix
  constructIP = subnet: suffix: let
    baseIP = extractIP subnet;
    baseParts = lib.splitString "." baseIP;
    baseOctets = lib.take 3 baseParts;
    # Extract the subnet mask from the original subnet
    subnetMask = lib.last (lib.splitString "/" subnet);
  in lib.concatStringsSep "." (baseOctets ++ [ suffix ]) + "/" + subnetMask;

  # Helper function to get the management interface name from mgmtInterface
  mgmtInterfaceName = lib.head (lib.attrNames mgmtInterface);

  # Helper function to get the management interface configuration
  mgmtInterfaceConfig = mgmtInterface.${mgmtInterfaceName};

  # Helper function to create VLAN network config
  createVlanNetwork = name: config: {
    "${name}" = {
      matchConfig.Name = config.name;
      networkConfig = {
        Address = [ (constructIP config.subnet4 (getNodeAddress config)) ];
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
      };
      linkConfig = {
        # VLAN interfaces need 4 bytes less MTU to account for 802.1q header
        MTUBytes = MTUBytes - 4;
      };
      inherit cakeConfig;
    };
  };

  # Helper function to create VLAN netdev config
  createVlanNetdev = name: config: {
    "${name}" = {
      netdevConfig = {
        Name = config.name;
        Kind = "vlan";
      };
      vlanConfig = {
        Id = config.id;
      };
    };
  };

  # Helper function to create bond slave network config
  createBondSlave = link: {
    "bond0-slave-${link}" = {
      matchConfig.Name = link;
      networkConfig = {
        Bond = bondConfig.Name;
        LLDP = true;
        EmitLLDP = true;
      };
      linkConfig = {
        MTUBytes = MTUBytes;
      };
    };
  };

  # Helper function to create WireGuard interface network config
  createWireGuardNetwork = interfaceName: interface: {
    "${interfaceName}" = {
      matchConfig.Name = interfaceName;
      networkConfig = {
        Address = [ interface.address ];
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
      };
      linkConfig = {
        MTUBytes = interface.mtu; # MTU is already in bytes
      };
      # Use interface-specific cake policy only if queue discipline is cake
    } // (lib.optionalAttrs (interface.queueDiscipline == "cake") {
      cakeConfig = interface.cakePolicy;
    });
  };

  # Get list of VLAN names for the bond0 interface
  vlanNames = map (name: vlanConfigs.${name}.name) (lib.attrNames vlanConfigs);

in {

  # Import WireGuard and failoverd configurations
  imports = [
    ./wireguard.nix
    ./keepalived.nix
  ];

  # https://nixos.wiki/wiki/Systemd-networkd
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network.enable = true;

  # Enable systemd-networkd in initrd for early network configuration
  #boot.initrd.systemd.network.enable = true;

  # DHCP needs to set the hostname, but we don't want to allow it
  # # Configure systemd-networkd service to allow hostname setting
  # # This is needed for DHCP and proper network configuration
  # systemd.services.systemd-networkd = {
  #   serviceConfig = {
  #     # Allow systemd-networkd to set the hostname (needed for DHCP)
  #     ProtectHostname = false;
  #     # Allow systemd-networkd to manage the hostname
  #     RestrictNamespaces = false;
  #     # Allow systemd-networkd to access the hostname
  #     RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
  #   };
  # };

  # https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html
  systemd.network.networks = {
    # Test management interface (eno1) - uses DHCP
    "test-mgmt" = {
      matchConfig.Name = testMgmtInterface;
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        LLDP = true;
        EmitLLDP = true;
      };
      linkConfig = {
        MTUBytes = MTUBytes;
      };
      inherit cakeConfig;
    };

    # Production management interface (enp1s0) - uses static IP
    "mgmt" = {
      matchConfig.Name = mgmtInterfaceName;
      networkConfig = {
        Address = [ (constructIP mgmtInterfaceConfig.subnet4 (getNodeAddress mgmtInterfaceConfig)) ];
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        LLDP = true;
        EmitLLDP = true;
      };
      linkConfig = {
        MTUBytes = MTUBytes;
      };
      inherit cakeConfig;
    };

    # Bond interface configuration
    "bond0" = {
      matchConfig.Name = bondConfig.Name;
      networkConfig = {
        Address = [
          (constructIP bondConfig.subnet4 (getNodeAddress bondConfig))
          #bondConfig.vrrp_ip # secondary IP
          #fd00::1/64" #FIXME!!
        ];
        LinkLocalAddressing = "no";
        # Note: Gateway is configured in routes section with high metric
        # to make it less preferred than DHCP route (metric 1024)
      };
      routes = [
        {
          Gateway = bondConfig.gateway_ip;
          Destination = "0.0.0.0/0"; # Default route (all destinations)
          Metric = 2000; # Higher than DHCP metric (1024) to make it less preferred
        }
      ];
      # IMPORTANT: systemd-networkd Route syntax requirements:
      # - Use "0.0.0.0/0" for IPv4 default routes (NOT "default")
      # - Use "::/0" for IPv6 default routes (NOT "default")
      # - "default" is NOT a valid Destination value in systemd-networkd
      # - Reference: https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html
      linkConfig = {
        #RequiredForOnline = "carrier";
        MTUBytes = MTUBytes;
      };
      vlan = vlanNames;
      inherit cakeConfig;
    };

    # Bond slave interfaces - generated from bondConfig.Links
  } // lib.foldl' (acc: link: acc // createBondSlave link) {} bondConfig.Links
    # VLAN interfaces - generated from vlanConfigs
    // lib.foldl' (acc: name: acc // createVlanNetwork name vlanConfigs.${name}) {} (lib.attrNames vlanConfigs);

  # Bond device configuration
  systemd.network.netdevs = {
    "bond0" = {
      netdevConfig = {
        Name = bondConfig.Name;
        Kind = "bond";
        MTUBytes = MTUBytes;
      };
      bondConfig = {
        Mode = "802.3ad";
        # MIIMonitorSec = "100ms";
        LACPTransmitRate = "fast"; # fast is only 1 second, so it's not really very fast :)
        TransmitHashPolicy = "layer3+4";
      };
    };

    # VLAN devices - generated from vlanConfigs
  } // lib.foldl' (acc: name: acc // createVlanNetdev name vlanConfigs.${name}) {} (lib.attrNames vlanConfigs);

}

# sudo cat /sys/class/net/bond0/bonding/mode
# sudo cat /sys/class/net/bond0/bonding/slaves
# sudo cat /sys/class/net/bond0/bonding/ad_actor_system