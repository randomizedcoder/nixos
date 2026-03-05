# udev-nic-names.nix
#
# Pin network interface names by MAC address for stability across reboots.
# This prevents interface name changes due to PCI enumeration order variations.
#
# Verify with: ip link show
# Debug udev: udevadm info -a /sys/class/net/<interface>

{ config, lib, pkgs, ... }:

{
  # Use systemd-networkd predictable names as base, then override specific NICs
  services.udev.extraRules = ''
    # Intel 82599ES 10GbE - DUT interfaces for mq-cake testing
    # PCI 42:00.0 and 42:00.1
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:1b:21:66:a9:80", NAME="ixgbe0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:1b:21:66:a9:81", NAME="ixgbe1"

    # Intel X710 10GbE SFP+ - Load generator interfaces
    # PCI 23:00.0 and 23:00.1
    # These already have stable names (enp35s0f0np0, enp35s0f1np1) but pin them for safety
    # Uncomment if needed:
    # SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="<mac0>", NAME="x710p0"
    # SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="<mac1>", NAME="x710p1"

    # Aquantia AQC107 10GbE - WAN interface
    # PCI 01:00.0
    # Already stable as enp1s0
  '';
}
