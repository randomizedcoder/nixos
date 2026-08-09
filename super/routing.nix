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

  # TCP-MD5 session authentication (same secret must be set on lf07/lf08's BGP neighbor
  # config, or the sessions won't authenticate — see bird-bgp-design.md). This lives in
  # the nix store (world-readable) and in git; acceptable for this internal fabric. Move
  # to agenix/sops-nix if you later want it out of the store. REPLACE the placeholder.
  bgpPassword = "REPLACE-WITH-SHARED-BGP-SECRET";

  # AS-path prepends added to the anycast advertisement. 2 on every node today, so all
  # servers advertise an equal (length-3) path and the ToRs ECMP evenly. This is a steering
  # lever for later: LOWER a node's count to PREFER it (shorter AS-path wins), RAISE it to
  # deprioritise. Set per-node overrides in the map below; default is 2.
  prependCount =
    { # "super-a" = 0;   # example: make super-a the preferred node
    }.${config.networking.hostName} or 2;
  prependStmts =
    lib.concatStrings (builtins.genList (_: "bgp_path.prepend(${toString localAs}); ") prependCount);

  # --- RTBH blackhole list (see rtbh-blackhole-design.md) ---
  # Always-on canary + any persistent bad-actor /32s advertised for the ToRs to drop
  # (source RTBH via loose uRPF). The canary's PRESENCE as Null0 on the ToRs proves the
  # whole pipeline end-to-end once BGP is up. High-rate / emergency drops go via the
  # kernel-666 fast-path (`ip route add blackhole <ip>/32 table 666`), not this list.
  blackholeList = [
    "192.0.2.66/32"     # CANARY (RFC 5737 TEST-NET-1) — safe, always-on pipeline check
    # Add VERIFIED bad-actor /32s below (from real threat intel — never a guessed block):
    # "203.0.113.7/32"
  ];
  blackholeRoutes =
    lib.concatMapStringsSep "\n" (p: "        route ${p} blackhole;") blackholeList;
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

      # Dedicated table for kernel-injected blackholes (Linux table 666); piped into
      # master4 below. Kept separate so it doesn't clash with the main kernel syncer.
      ipv4 table blackhole4;

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

      # RTBH guardrail: prefixes we must NEVER blackhole (our own space / infra). Extend
      # with any network you can't afford to accidentally drop.
      define PROTECTED = [ 10.241.10.0/24+, 10.240.10.0/24+ ];

      # Inbound: deny bogons first, accept only expected prefixes, else default-deny.
      filter tor_in {
        if net ~ BOGONS   then reject;
        if net ~ ACCEPT_IN then accept;
        reject;
      }
      # Outbound: advertise only what we originate (with AS-path prepends for steering
      # headroom — see prependCount above), else deny.
      filter tor_out {
        # RTBH: a locally-injected blackhole route -> tag BLACKHOLE (RFC 7999) + advertise,
        # but ONLY host routes (/32) and NEVER our own protected space (anti-footgun).
        if dest = RTD_BLACKHOLE then {
          if net.len != 32 then reject;
          if net ~ PROTECTED then reject;
          bgp_community.add((65535, 666));
          accept;
        }
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

      # RTBH sources (advertise-only; NOT installed in this node's FIB, since the main
      # kernel proto above exports only RTS_BGP). See rtbh-blackhole-design.md.
      #   (A) declarative list: canary + persistent bad actors (from blackholeList).
      protocol static blackhole_src {
        ipv4;
${blackholeRoutes}
      }
      #   (B) operational fast-path: pull blackholes from Linux table 666, so
      #   `ip route add blackhole <ip>/32 table 666` advertises instantly (no rebuild).
      #   Imports into a dedicated table, then a pipe copies blackholes into master4.
      protocol kernel bh_inject {
        learn;                 # import routes BIRD didn't originate (the injected blackholes)
        kernel table 666;
        ipv4 { table blackhole4; import all; export none; };
      }
      protocol pipe bh_pipe {
        table master4;
        peer table blackhole4;
        import where dest = RTD_BLACKHOLE;   # blackhole4 -> master4 (advertise), blackholes only
        export none;                          # nothing master4 -> blackhole4
      }

      # eBGP to each ToR — filtered both ways (see tor_in / tor_out above).
      # Session options (Tier 1 — see bird-bgp-design.md). Tier 2 (BFD, ttl security)
      # is documented there and can be enabled later alongside the matching ToR config.
      template bgp tor {
        local as ${toString localAs};
        password "${bgpPassword}";   # TCP-MD5 (needs the same secret on the ToR)
        graceful restart on;         # keep forwarding across a BIRD restart
        check link on;               # drop the session immediately if bond0.401 loses carrier
        enforce first as on;         # reject routes whose AS-path doesn't start with the ToR's AS
        ipv4 {
          import filter tor_in;
          import keep filtered on;   # retain rejected routes for `birdc show route filtered`
          export filter tor_out;
        };
      }
      protocol bgp tor_lf07 from tor {
        source address ${selfIp};
        neighbor ${torLf07} as ${toString torAs};
      }
      protocol bgp tor_lf08 from tor {
        source address ${selfIp};
        neighbor ${torLf08} as ${toString torAs};
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
