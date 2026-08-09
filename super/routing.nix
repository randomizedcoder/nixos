#
# /etc/nixos/routing.nix  —  identical on every super-* node
#
# Node-side routing for the Supermicro pod. Companion to networking.nix (which owns the
# bond + VLAN 401 IP + MTU). This file owns *routing*:
#
#   * BIRD (bird3) eBGP to BOTH ToRs (lf07 .2 / lf08 .3), AS65200 -> AS65100:
#       - IMPORT only the default (0.0.0.0/0) and install it ECMP (both next-hops) in the
#         kernel, per-flow hashed;
#       - EXPORT only the anycast service VIP 10.241.10.20/32.
#   * The anycast VIP on loopback (so the host answers for it; advertised by BIRD).
#   * A low-preference STATIC fallback default via the VRRP VIP .1 (metric 4000) so that
#     internet/VPN work WITHOUT BGP — used at boot and whenever BIRD is down. BGP's ECMP
#     default (lower metric) wins whenever it is up.
#
# Design + rationale: ../nfb-ladc-asa01/bird-bgp-design.md. Per-node values are derived
# from the hostname, so this file is identical on every node (super-a->.10 ... super-d->.13).
#
{ config, lib, ... }:

let
  octet =
    { "super-a" = 10; "super-b" = 11; "super-c" = 12; "super-d" = 13; }
    .${config.networking.hostName}
      or (throw "routing.nix: no VLAN401 octet for hostname '${config.networking.hostName}' — add it to the map");

  selfIp     = "10.241.10.${toString octet}";  # this node's BGP source / router-id
  torLf07    = "10.241.10.2";                   # lf07 Vlan401 SVI (eBGP peer)
  torLf08    = "10.241.10.3";                   # lf08 Vlan401 SVI (eBGP peer)
  vrrpVip    = "10.241.10.1";                   # VLAN401 gateway = static fallback next-hop
  anycastVip = "10.241.10.20";                  # anycast service VIP (advertised via BGP)
  localAs    = 65200;                            # this node's (server) ASN
  torAs      = 65100;                            # the ToRs' ASN

  # AS-path prepends added to the anycast advertisement. 2 on every node today, so all
  # servers advertise an equal (length-3) path and the ToRs ECMP evenly. This is a steering
  # lever for later: LOWER a node's count to PREFER it (shorter AS-path wins), RAISE it to
  # deprioritise. Set per-node overrides in the map below; default is 2.
  prependCount =
    { # "super-a" = 0;   # example: make super-a the preferred node
    }.${config.networking.hostName} or 2;
  prependStmts =
    lib.concatStrings (builtins.genList (_: "bgp_path.prepend(${toString localAs}); ") prependCount);
in
{
  # LLDP so the node shows up in the ToRs' neighbour tables (and we can see the ToRs).
  services.lldpd.enable = true;

  # --- BIRD (bird3; config is validated at build time by checkConfig) ---
  services.bird = {
    enable = true;
    checkConfig = true;
    config = ''
      router id ${selfIp};
      log syslog all;

      # ============================ Route policy ============================
      # Belt-and-braces filtering on BOTH ToR sessions. To advertise/accept more,
      # just add a prefix to ORIGINATE / ACCEPT_IN below — the filters pick it up.

      # OUTBOUND allow-list: exactly what this node originates. Today: the anycast VIP.
      define ORIGINATE = [ ${anycastVip}/32 ];

      # INBOUND allow-list: exactly what we expect to receive. Today: the default only.
      define ACCEPT_IN = [ 0.0.0.0/0 ];

      # Bogons/martians we must NEVER accept — checked FIRST, before ACCEPT_IN.
      # NOTE: 10.0.0.0/8 is denied on purpose; this default-only design never expects to
      # learn any 10/8 from BGP. If you later import an internal aggregate, adjust this.
      define BOGONS = [
          0.0.0.0/8+,          # this-network (the default 0.0.0.0/0 is NOT matched by /8+)
          10.0.0.0/8+,         # RFC1918 (see note above)
          100.64.0.0/10+,      # CGNAT (RFC6598)
          127.0.0.0/8+,        # loopback
          169.254.0.0/16+,     # link-local
          172.16.0.0/12+,      # RFC1918
          192.0.2.0/24+,       # TEST-NET-1
          192.168.0.0/16+,     # RFC1918
          198.18.0.0/15+,      # benchmarking
          198.51.100.0/24+,    # TEST-NET-2
          203.0.113.0/24+,     # TEST-NET-3
          224.0.0.0/4+,        # multicast
          240.0.0.0/4+         # reserved (incl. 255.255.255.255 broadcast)
      ];

      # Inbound: deny bogons first, accept only expected prefixes, else default-deny.
      filter tor_in {
        if net ~ BOGONS   then reject;
        if net ~ ACCEPT_IN then accept;
        reject;
      }
      # Outbound: advertise only what we originate (with AS-path prepends for steering
      # headroom — see prependCount above), else deny.
      filter tor_out {
        if net ~ ORIGINATE then { ${prependStmts}accept; }
        reject;
      }
      # ======================================================================

      protocol device { }

      # Pick up the anycast VIP from loopback so BGP can advertise it (VIP only, not 127/8).
      protocol direct {
        interface "lo";
        ipv4 { import where net = ${anycastVip}/32; };
      }

      # Install ONLY BGP-learned routes (the ECMP default) into the kernel FIB.
      protocol kernel {
        ipv4 { import none; export where source = RTS_BGP; };
        merge paths on;        # ECMP: one default with both ToR next-hops
      }

      # eBGP to each ToR — filtered both ways (see tor_in / tor_out above).
      protocol bgp tor_lf07 {
        local ${selfIp} as ${toString localAs};
        neighbor ${torLf07} as ${toString torAs};
        ipv4 { import filter tor_in; export filter tor_out; };
      }
      protocol bgp tor_lf08 {
        local ${selfIp} as ${toString localAs};
        neighbor ${torLf08} as ${toString torAs};
        ipv4 { import filter tor_in; export filter tor_out; };
      }
    '';
  };

  # Anycast VIP on loopback: the host answers for it; the ToRs reach it via the BGP
  # next-hop (this node's .x), so it never needs to ARP on the L2.
  networking.interfaces.lo.ipv4.addresses = [
    { address = anycastVip; prefixLength = 32; }
  ];

  boot.kernel.sysctl = {
    "net.ipv4.fib_multipath_hash_policy" = 1;   # per-flow (L4) ECMP hashing
    "net.ipv4.conf.all.arp_ignore"       = 1;   # never ARP-reply for the VIP on bond0.401
    "net.ipv4.conf.all.arp_announce"     = 2;   # use best local source in ARP
  };

  # Static fallback default via the VRRP VIP, high metric so BGP's ECMP default wins when
  # BIRD is up. This is what makes internet/VPN work WITHOUT BGP (boot / BIRD down).
  networking.interfaces."bond0.401".ipv4.routes = [
    { address = "0.0.0.0"; prefixLength = 0; via = vrrpVip; options.metric = "4000"; }
  ];
}
