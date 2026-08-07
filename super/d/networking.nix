# ~/nixos/super/d/networking.nix   —  node d (nodeD)
#
# Data-plane networking + host integration for the default (non-flake) install.
# Self-contained: the only edit needed in configuration.nix is adding
# ./networking.nix to imports — the mkForce lines override the stock
# NetworkManager / DHCP / hostname defaults without hand-editing them.
#
# LACP (802.3ad) bond across the two onboard 10G NICs into the switches'
# multi-chassis LAG. The switch server ports are TRUNKS (Nexus vPC 220,
# "switchport trunk allowed vlan 400-401"), so VLAN 401 is delivered TAGGED —
# the IP lives on the bond0.401 VLAN interface, not on bond0 directly.
# NIC MACs are from the node's BMC web UI. See
# ~/Downloads/nfb-ladc-asa01/dave-servers.md.
{ lib, ... }:
{
  # --- host integration: override the stock install's defaults ---
  networking.hostName = lib.mkForce "nodeD";
  networking.networkmanager.enable = lib.mkForce false;   # bond runs on networkd now
  users.users.das.extraGroups = lib.mkForce [ "wheel" ];  # drop "networkmanager" (group gone once NM is off)

  networking.useNetworkd = true;
  networking.useDHCP = lib.mkForce false;

  # Optional but recommended: your key -> passwordless SSH once the IP is up.
  users.users.das.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
  ];

  # --- LACP bond -> Nexus vPC 220 (trunk, tagged VLAN 400-401) ---
  systemd.network.netdevs."10-bond0" = {
    netdevConfig = { Name = "bond0"; Kind = "bond"; };
    bondConfig = {
      Mode = "802.3ad";
      TransmitHashPolicy = "layer3+4";
      LACPTransmitRate = "fast";
      MIIMonitorSec = "0.1";
    };
  };

  # VLAN 401 tag on top of the bond (switch trunk delivers 401 tagged).
  systemd.network.netdevs."15-bond0.401" = {
    netdevConfig = { Name = "bond0.401"; Kind = "vlan"; };
    vlanConfig.Id = 401;
  };

  # Enslave both onboard 10G ports by permanent (hardware) MAC.
  systemd.network.networks."30-bond-member-lan1" = {
    matchConfig.PermanentMACAddress = "ac:1f:6b:15:d7:64";  # node d  System LAN1
    networkConfig.Bond = "bond0";
  };
  systemd.network.networks."30-bond-member-lan2" = {
    matchConfig.PermanentMACAddress = "ac:1f:6b:15:d7:65";  # node d  System LAN2
    networkConfig.Bond = "bond0";
  };

  # bond0 itself carries no IP — it just trunks the VLAN up to the switch.
  systemd.network.networks."40-bond0" = {
    matchConfig.Name = "bond0";
    networkConfig.LinkLocalAddressing = "no";
    vlan = [ "bond0.401" ];
    linkConfig.RequiredForOnline = "carrier";
  };

  # The VLAN 401 interface holds the static IP.
  systemd.network.networks."45-bond0.401" = {
    matchConfig.Name = "bond0.401";
    address = [ "10.241.10.13/24" ];   # node d
    gateway = [ "10.241.10.1" ];       # VLAN 401 gateway — not configured in the fabric yet
    dns = [ "1.1.1.1" "9.9.9.9" ];
    linkConfig.RequiredForOnline = "carrier";
  };
}
