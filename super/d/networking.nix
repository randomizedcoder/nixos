#
# /etc/nixos/networking.nix  —  identical on every super-* node
#
# LACP (802.3ad) bond of the two onboard 10G NICs (eno1 + eno2) into the Nexus
# vPC pair, with the host IP on the *tagged* VLAN 401 sub-interface (bond0.401).
# The leaf ports are 802.1q trunks (`switchport trunk allowed vlan 400-401`), so
# the IP must be tagged on bond0.401 — an untagged IP on bond0 lands on the
# trunk's native VLAN (1, not allowed) and is dropped.
#
# NICs are always eno1/eno2, so we bond by name — which of the two is which does
# not matter for LACP. The per-node IP is derived from the hostname, so this file
# is the same on all nodes:  super-a->.10  super-b->.11  super-c->.12  super-d->.13
#
{ config, lib, ... }:

let
  vlan401Octet =
    { "super-a" = 10; "super-b" = 11; "super-c" = 12; "super-d" = 13; }
    .${config.networking.hostName}
      or (throw "networking.nix: no VLAN401 IP for hostname '${config.networking.hostName}' — add it to vlan401Octet");

  # MTU: keep at 1500 for now. Jumbo (9000) must ONLY be enabled AFTER both leaves carry
  # the network-qos JUMBO policy — otherwise oversized frames the node *sends* blackhole on
  # the switch (which broke node->internet downloads). Raise to 9000 once jumbo is confirmed
  # end-to-end (host IP-MTU 9000 + 14 eth + 4 tag = 9018 < the 9216 fabric ceiling).
  mtu = 1500;
in
{
  # This module drives the interfaces; keep NetworkManager and DHCP off them.
  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;

  # 802.3ad (LACP) bond across both onboard 10G NICs.
  networking.bonds.bond0 = {
    interfaces = [ "eno1" "eno2" ];
    driverOptions = {
      mode = "802.3ad";
      lacp_rate = "fast";        # match `lacp rate fast` on the Nexus po
      xmit_hash_policy = "layer3+4";
      miimon = "100";
    };
  };

  # VLAN 401 is tagged on the trunk -> host IP goes on bond0.401, not the raw bond.
  networking.vlans."bond0.401" = {
    id = 401;
    interface = "bond0";
  };

  networking.interfaces."bond0.401".ipv4.addresses = [
    { address = "10.241.10.${toString vlan401Octet}"; prefixLength = 24; }
  ];

  # Jumbo MTU across the whole data path (slaves -> bond -> tagged VLAN).
  networking.interfaces.eno1.mtu = mtu;
  networking.interfaces.eno2.mtu = mtu;
  networking.interfaces.bond0.mtu = mtu;
  networking.interfaces."bond0.401".mtu = mtu;

  # NOTE: the default route now lives in routing.nix, NOT here. BIRD installs an ECMP
  # default via the two ToR SVIs (.2/.3) at low metric, with a STATIC fallback via the
  # VRRP VIP .1 at metric 4000 (so internet/VPN work even without BGP). A metric-0
  # `networking.defaultGateway` here would collide with the BGP default, so it is
  # intentionally omitted. Deploy networking.nix + routing.nix together; networking.nix
  # alone leaves the node intra-VLAN only (no default route).

  # DNS (static config, no DHCP -> no resolver otherwise). Public resolvers reachable
  # once the ASA internet PAT for VLAN 401 is in place.
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
}
