#
# /etc/nixos/routing.nix  —  identical on every super-* node
#
# Node-side routing for the Supermicro pod. Companion to networking.nix (which owns the
# bond + VLAN 401 IP + MTU). This file owns *routing*:
#
#   * BIRD (bird3) eBGP to BOTH ToRs (lf07 .2 / lf08 .3), AS65200 -> AS65100:
#       - IMPORT only the default (0.0.0.0/0) and install it ECMP (both next-hops) in the
#         kernel, per-flow hashed;
#       - EXPORT the anycast service VIP 10.241.10.20/32 + this node's PUBLIC /32s (its own
#         unicast + the shared public anycast) — see ../nfb-ladc-asa01/public-ip-anycast/design.md.
#   * The anycast VIP + public /32s on loopback (so the host answers for them; advertised by BIRD).
#   * A low-preference STATIC fallback default via the VRRP VIP .1 (metric 4000) so that
#     internet/VPN work WITHOUT BGP — used at boot and whenever BIRD is down. BGP's ECMP
#     default (lower metric) wins whenever it is up.
#
# Design + rationale: ../nfb-ladc-asa01/bird-bgp-design.md. Per-node values are derived
# from the hostname, so this file is identical on every node (super-a->.10 ... super-d->.13).
#
{ config, lib, pkgs, ... }:

let
  octet =
    { "super-a" = 10; "super-b" = 11; "super-c" = 12; "super-d" = 13; }
    .${config.networking.hostName}
      or (throw "routing.nix: no VLAN401 octet for hostname '${config.networking.hostName}' — add it to the map");

  selfIp     = "10.241.10.${toString octet}";  # this node's BGP source / router-id
  torLf07    = "10.241.10.2";                   # lf07 Vlan401 SVI (eBGP peer)
  torLf08    = "10.241.10.3";                   # lf08 Vlan401 SVI (eBGP peer)
  vrrpVipA   = "10.241.10.1";                   # VLAN401 VRRP VIP-A (lf07 master) — fallback nexthop
  vrrpVipB   = "10.241.10.4";                   # VLAN401 VRRP VIP-B (lf08 master) — fallback nexthop
  anycastVip = "10.241.10.20";                  # internal anycast service VIP (advertised via BGP)

  # Public /32s — DAVE-namespaced (see ../nfb-ladc-asa01/public-ip-anycast/design.md).
  #   davePublicUnicast : this node's own public IP (only this node originates it).
  #   davePublicAnycast : shared public anycast (every node originates it -> ECMP at the ToRs).
  davePublicUnicast =
    { "super-a" = "160.72.197.234"; "super-b" = "160.72.197.235";
      "super-c" = "160.72.197.236"; "super-d" = "160.72.197.237"; }
    .${config.networking.hostName}
      or (throw "routing.nix: no public /32 for hostname '${config.networking.hostName}' — add it to davePublicUnicast");
  davePublicAnycast = "160.72.197.238";

  localAs    = 65200;                            # this node's (server) ASN
  torAs      = 65100;                            # the ToRs' ASN

  # TCP-MD5 session authentication (same secret must be set on lf07/lf08's BGP neighbor
  # config, or the sessions won't authenticate — see bird-bgp-design.md). This lives in
  # the nix store (world-readable) and in git; acceptable for this internal fabric. Move
  # to agenix/sops-nix if you later want it out of the store. REPLACE the placeholder.
  bgpPassword = "bgpPassword";

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

      # OUTBOUND allow-list(s): exactly what this node originates.
      #   ORIGINATE   = the internal anycast service VIP.
      #   DAVE_PUBLIC = the public /32s (this node's unicast + the shared public anycast).
      # Kept as TWO sets, combined with `||` at each use-site below: BIRD does not allow a set
      # constant to be nested inside another set literal (`[ x/32, DAVE_PUBLIC ]` is a syntax
      # error), so we can't fold them into one. Add a prefix to either set to advertise more.
      define ORIGINATE   = [ ${anycastVip}/32 ];
      define DAVE_PUBLIC = [ ${davePublicUnicast}/32, ${davePublicAnycast}/32 ];

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
        if net ~ ORIGINATE || net ~ DAVE_PUBLIC then { ${prependStmts}accept; }
        reject;
      }
      # ======================================================================

      protocol device { }

      # Pick up the originated addresses from the service dummies so BGP can advertise them
      # (dummy0 = per-node unicast, dummy1 = anycast .20/.238). The match (ORIGINATE ||
      # DAVE_PUBLIC) is exactly those /32s. On dummies, NOT lo — see the interface block below.
      protocol direct {
        interface "dummy0", "dummy1";
        ipv4 { import where net ~ ORIGINATE || net ~ DAVE_PUBLIC; };
      }

      # Install ONLY BGP-learned routes (the ECMP default) into the kernel FIB.
      protocol kernel {
        metric 20;             # kernel route metric = eBGP AD (Cisco convention). Cosmetic:
                               # any value < the 4000 static fallback makes BGP win. (Default 32.)
        ipv4 {
          import none;
          # Export BGP-learned routes (the ECMP default) and pin their route MTU to 1500.
          # This makes the node cap OFF-subnet (north-south) traffic at 1500 AT THE SOURCE —
          # no PMTUD/ICMP dependency and no ASA MSS-clamp (which would burn firewall CPU).
          # ON-subnet (east-west) traffic uses the connected 10.241.10.0/24 route, which
          # inherits the 9000 interface MTU. So: node<->node = 9000, node->internet = 1500.
          export filter {
            if source != RTS_BGP then reject;
            krt_mtu = 1500;
            accept;
          };
        };
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
      # Session options: Tier 1 + GTSM (ttl security) — see bird-bgp-design.md. BFD (Tier 2)
      # is documented there and can be enabled later alongside the matching ToR config.
      template bgp tor {
        local as ${toString localAs};
        password "${bgpPassword}";   # TCP-MD5 (needs the same secret on the ToR)
        hold time 9;                 # fast soft-failure detection (default 240). check link
        keepalive time 3;            # covers cable pulls instantly; these catch a dead BGP
                                     # process. Match on the ToR: `timers 3 9`.
        graceful restart on;         # keep forwarding across a BIRD restart
        check link on;               # drop the session immediately if bond0.401 loses carrier
        enforce first as on;         # reject routes whose AS-path doesn't start with the ToR's AS
        ttl security on;             # GTSM (RFC 5082): send TTL 255, require it inbound — drops any
                                     # spoofed/multi-hop session attempt. Needs `ttl-security hops 1`
                                     # on the ToR neighbor (paired change) or the session won't come up.
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

  # Service /32s live on TWO dedicated dummy loopbacks, NOT on `lo`. Rationale: NixOS
  # scripted-networking's `network-addresses-lo.service` has no WantedBy and nothing starts it
  # at boot (a real NIC's address service is WantedBy its udev device; `lo`'s is not, and
  # `network-setup.service` doesn't exist on this release), so `lo` secondary addresses
  # silently never apply. A dummy IS a real device, so its `network-addresses-dummyN.service`
  # is BindsTo/WantedBy `sys-subsystem-net-devices-dummyN.device` — it applies reliably and is
  # reboot-safe. The host answers for these /32s; the ToRs reach them via the BGP next-hop
  # (this node's .x), so they never ARP on the L2 (arp_ignore below).
  boot.kernelModules = [ "dummy" ];
  boot.extraModprobeConfig = "options dummy numdummies=2";   # create dummy0 + dummy1 at load
  networking.interfaces.dummy0.ipv4.addresses = [
    { address = davePublicUnicast; prefixLength = 32; }      # per-node public unicast /32
  ];
  networking.interfaces.dummy1.ipv4.addresses = [
    { address = anycastVip;        prefixLength = 32; }      # internal anycast .20
    { address = davePublicAnycast; prefixLength = 32; }      # public anycast .238
  ];

  boot.kernel.sysctl = {
    "net.ipv4.fib_multipath_hash_policy" = 1;   # per-flow (L4) ECMP hashing
    "net.ipv4.conf.all.arp_ignore"       = 1;   # never ARP-reply for the VIP on bond0.401
    "net.ipv4.conf.all.arp_announce"     = 2;   # use best local source in ARP
  };

  # Fallback default route — ECMP across BOTH VLAN401 VRRP VIPs (.1 = lf07-master,
  # .4 = lf08-master), so the no-BGP / boot path also spreads node->ToR flows across both
  # ToRs. Metric 4000 so BGP's native ECMP default (via .2/.3, `merge paths`) wins whenever
  # BIRD is up. Linux can't ECMP two same-metric default routes added separately, so this is
  # ONE multipath route.
  #
  # Installed via networking.localCommands, which runs at the END of network-setup — i.e.
  # AFTER bond0.401 has its IP — so there's no boot race. (A prior systemd oneshot could
  # lose that race against the bond/LACP coming up and leave the node with no default at
  # all; localCommands is ordered correctly by construction.)
  networking.localCommands = ''
    for _ in 1 2 3 4 5; do
      ip route replace default metric 4000 mtu 1500 \
        nexthop via ${vrrpVipA} dev bond0.401 \
        nexthop via ${vrrpVipB} dev bond0.401 && break
      sleep 1
    done
  '';
}
