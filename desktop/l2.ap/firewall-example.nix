# Example firewall configurations for different machines
# Copy this file and customize the variables for your specific machine

# Example 1: L2 WiFi Access Point (current configuration)
{ config, pkgs, ... }:

let
  # Interface configuration for L2 machine
  wanInterface = "enp1s0";      # External/WAN interface
  lanInterface = "br0";         # Internal/LAN bridge interface
  upstreamLanPrefix = "172.16.0.0/16";  # Upstream LAN prefix for management access
  internalIPv4Prefix = "192.168.1.0/24"; # Internal IPv4 subnet
  internalIPv6Prefix = "fd00::/64";      # Internal IPv6 subnet
in {
  # Import the main firewall configuration
  imports = [ ./firewall.nix ];
}

# Example 2: Different machine with different interface names
/*
{ config, pkgs, ... }:

let
  # Interface configuration for different machine
  wanInterface = "eth0";        # External/WAN interface (different name)
  lanInterface = "wlan0";       # Internal/LAN interface (WiFi instead of bridge)
  upstreamLanPrefix = "10.0.0.0/8";   # Different upstream LAN
  internalIPv4Prefix = "192.168.100.0/24"; # Different internal subnet
  internalIPv6Prefix = "fd01::/64";         # Different internal IPv6 subnet
in {
  # Import the main firewall configuration
  imports = [ ./firewall.nix ];
}
*/

# Example 3: Server with multiple interfaces
/*
{ config, pkgs, ... }:

let
  # Interface configuration for server
  wanInterface = "eno1";        # External/WAN interface
  lanInterface = "eno2";        # Internal/LAN interface (separate NIC)
  upstreamLanPrefix = "172.20.0.0/16"; # Different upstream network
  internalIPv4Prefix = "10.10.0.0/24";  # Different internal subnet
  internalIPv6Prefix = "fd02::/64";     # Different internal IPv6 subnet
in {
  # Import the main firewall configuration
  imports = [ ./firewall.nix ];
}
*/

# Example 4: Virtual machine
/*
{ config, pkgs, ... }:

let
  # Interface configuration for VM
  wanInterface = "ens3";        # External/WAN interface (VM naming)
  lanInterface = "ens4";        # Internal/LAN interface
  upstreamLanPrefix = "192.168.122.0/24"; # Libvirt default network
  internalIPv4Prefix = "192.168.200.0/24"; # VM internal subnet
  internalIPv6Prefix = "fd03::/64";        # VM internal IPv6 subnet
in {
  # Import the main firewall configuration
  imports = [ ./firewall.nix ];
}
*/