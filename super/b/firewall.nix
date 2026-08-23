#
# /etc/nixos/firewall.nix  —  identical on every super-* node
#
# Host firewall (nftables) for the Supermicro pod. Defense-in-depth BEHIND the ASA:
# the ASA CCFiber_access ACL is the perimeter; this is the on-host enforcement. Stance:
# "we do not trust packets from the internet" — default-drop input, only the exact services
# the ASA permits opened, SSH gated behind a port-knock, and a comprehensive anti-DoS /
# invalid-traffic filtering layer (these nodes run a commercial internet-facing service and
# WILL see automated / botnet / ransom-style attacks).
#
# See ../nfb-ladc-asa01/host-firewall-design.md for the full design + strategy, and
# ../nfb-ladc-asa01/public-ip-anycast/design.md for the addressing / ASA matrix.
#
# TRUST MODEL (this is an ENDPOINT, not a router, and everything — RFC1918 fabric AND
# public traffic — ingresses on bond0.401, so the trust split is by ADDRESS not interface):
#   * trusted SOURCES (cfg.trustedNets) = the local fabric 10.241.10.0/24 AND the
#       remote-access VPN pool 10.200.20.0/27  -> accept unconditionally (FIRST, after lo).
#       This is what keeps BGP (to lf07 .2 / lf08 .3, GTSM TTL 255 + MD5, hold 9s),
#       fabric-side management SSH, VRRP, AND the operator's VPN SSH (e.g. 10.200.20.1)
#       alive through the enable transition and every nft reload — trusted packets are
#       never subjected to blackhole / ct-state / flag / bogon / rate hygiene.
#   * traffic to the public /32s from anything else = untrusted internet -> only the
#       ASA-matrix services, per-source rate/conn limited, plus the knock-gated SSH.
#
# HARDENING LAYERS (internet path), in order: blackhole set (incident response / future
# auto-ban) -> ct invalid -> source-routing & bad-MSS & TCP-flag drops -> martian/bogon
# anti-spoof -> PER-SOURCE rate + connection meters on every public service -> knock-gated
# SSH. Pairs with the security sysctls set below (syncookies, no source-route/redirects,
# conntrack sizing). See design doc §"Invalid Traffic Filtering / anti-DoS".
#
# NOTES:
#   * nft reload is ATOMIC (single transaction) — established conntrack, incl. BGP, is
#     preserved across a `switch`, so restartIfChanged default is fine (no BGP flap).
#   * rp_filter is set to LOOSE (2), NOT strict (1): the public /32s live on dummy0/dummy1
#     and their traffic ingresses on bond0.401, and the default route is BGP-ECMP/anycast —
#     strict RPF would drop those asymmetric/multipath paths. Loose still drops truly
#     unroutable sources; the nft martian/bogon sets do the rest.
#   * All per-source meters are SIZED dynamic sets (cfg.limits.meterSize) so a spoofed-source
#     flood can't exhaust memory; when a meter set fills it fails OPEN (accept) rather than
#     locking out legitimate clients — the ASA + blackhole are the backstop.
#   * Hygiene lives AFTER `ct established,related accept`, so it only judges NEW/untracked
#     packets — existing flows aren't caught out when the firewall is first switched on.
#   * IPv6 is OFF for now (cfg.ipv6 = false): the fabric is IPv4-only, so all inbound v6
#     (except loopback) is dropped and the v6 filter rules are omitted. Those v6 rules stay
#     in-source behind the flag — flip cfg.ipv6 to true and rebuild when v6 is enabled.
#
{ config, lib, pkgs, ... }:

let
  # ─────────────────────────────────────────────────────────────────────────────
  #  cfg — the ONE place to edit values. Everything below interpolates from here.
  # ─────────────────────────────────────────────────────────────────────────────
  cfg = {
    # Trusted SOURCE networks — accepted unconditionally, FIRST, to ALL ports (they bypass
    # all blackhole / ct-state / flag / bogon / rate hygiene). Keep tight: infra ranges only.
    trustedNets = [
      "10.241.10.0/24"    # local fabric: BGP peers (lf07/lf08), VRRP, fabric-side mgmt SSH
      "10.200.20.0/27"    # remote-access VPN pool — operator SSH (de-risks the rollout).
                          # Matches ASA `ip local pool LADCVPN 10.200.20.1-10.200.20.30
                          # mask 255.255.255.224` (asa-config-2026_08_08_1735 l21).
    ];

    anycast = "160.72.197.238";                   # shared public anycast /32 (all nodes)
    publicUnicast = {                             # per-node public unicast /32 (this node only)
      "super-a" = "160.72.197.234"; "super-b" = "160.72.197.235";
      "super-c" = "160.72.197.236"; "super-d" = "160.72.197.237";
    };

    ports = {
      ssh      = 22;      # SSH        — fabric always; internet only after a knock
      knock    = 44;      # port-knock — a new TCP here authorizes the source for SSH
      http     = 80;      # nginx      — 80 -> 443 redirect
      https    = 443;     # nginx
      kafka    = 9093;    # Kafka TLS
      dns      = 53;      # DNS        — anycast only (tcp + udp)
      iperfTcp = 5001;    # iperf2 tcp — anycast only (testing)
      iperfUdp = 5002;    # iperf2 udp — anycast only (testing)
    };

    sshClientTimeout = "1h";       # how long a knock keeps SSH open for that source

    # IPv6: the network is IPv4-only TODAY. false = DROP all inbound v6 (except loopback) and
    # OMIT the v6 filter rules — which stay in-source below, behind this flag, ready to go.
    # Flip to true (and rebuild) once IPv6 is enabled on the fabric.
    ipv6 = false;

    # Per-SOURCE limits on the public services (moderate defaults). Keyed by `ip saddr` via
    # SIZED dynamic sets, so one noisy source can't starve everyone (a global limit would
    # self-DoS) and can't exhaust memory. Headroom left for a NAT'd office sharing one IP.
    limits = {
      pubConns    = 600;            # max concurrent NEW conns per source (web/kafka)
      pubNewRate  = "500/second";   # max new-conn rate per source (web/kafka/dns)
      pubNewBurst = 1000;           # burst packets for the rate meters
      icmpEcho    = "100/second";   # inbound ping per source
      icmpBurst   = 200;
      sshNewRate  = "100/second";   # per-source new SSH / knock rate (defense in depth)
      sshBurst    = 200;
      meterSize   = 256000;         # cap on distinct sources tracked per meter (bounds memory,
                                    # NOT a per-source throttle — left as-is)
    };

    # WireGuard remote access. The firewall PLUMBING ships now (open the port + forward +
    # masquerade) but is INERT until a wireguard.nix creates wg0. Then an operator can WG to
    # a node's unicast /32 (pick a node) or the anycast .238 (land on whichever node ECMP
    # hashes to; the session pins there) and reach the whole 10.241.10.0/24 fabric.
    #   Access model = masquerade: WG-client traffic is SNAT'd to the node's bond0.401 IP,
    #   so the fabric needs NO return-route changes. Requires ip_forward = 1 (set below).
    #   The deferred wireguard.nix must bind BOTH the unicast and the anycast address.
    #   ASA: add a UDP/250 permit -> the public /32s when WG is turned on (user applies).
    wireguard = {
      interface    = "wg0";
      listenPort   = 250;                # UDP
      tunnelSubnet = "10.9.250.0/24";    # PLACEHOLDER — confirm when enabling WG
    };
  };

  selfUnicast = cfg.publicUnicast.${config.networking.hostName}
    or (throw "firewall.nix: no public unicast /32 for hostname '${config.networking.hostName}' — add it to cfg.publicUnicast");

  p  = cfg.ports;
  L  = cfg.limits;
  wg = cfg.wireguard;
  trustedElems = lib.concatStringsSep ", " cfg.trustedNets;   # -> nftables set elements
  # dave_public = the two public addresses THIS node answers for (own unicast + shared anycast)
  davePublicElems = "${selfUnicast}, ${cfg.anycast}";

  # per-source rate/conn drop-expressions (interpolated into the rules below)
  rlPub  = "limit rate over ${L.pubNewRate} burst ${toString L.pubNewBurst} packets";
  rlSsh  = "limit rate over ${L.sshNewRate} burst ${toString L.sshBurst} packets";
  rlIcmp = "limit rate over ${L.icmpEcho} burst ${toString L.icmpBurst} packets";

  # ── IPv6 rule fragments — emitted only when cfg.ipv6 is true (kept in-source otherwise) ──
  v6Sets = lib.optionalString cfg.ipv6 ''
        set special_purpose_ipv6 {
          type ipv6_addr
          flags interval
          elements = {
            ::1/128,             # Loopback
            ::/128,              # Unspecified
            64:ff9b::/96,        # IPv4/IPv6 translation
            ::ffff:0:0/96,       # IPv4-mapped
            100::/64,            # Discard-only
            2001::/32,           # TEREDO
            2001:2::/48,         # Benchmarking
            2001:db8::/32,       # Documentation
            2002::/16,           # 6to4
            fc00::/7,            # Unique-local
            fe80::/10,           # Link-local
            ff00::/8             # Multicast
          }
        }
        set bogon_ipv6 { type ipv6_addr; flags interval; auto-merge; }
        set blackhole_v6 { type ipv6_addr; flags interval, timeout; }'';

  v6Disabled  = lib.optionalString (!cfg.ipv6)
    "meta nfproto ipv6 counter drop   # IPv6 disabled (v4-only network) — flip cfg.ipv6 to enable";
  v6Blackhole = lib.optionalString cfg.ipv6 "ip6 saddr @blackhole_v6 drop";
  v6AntiSpoof = lib.optionalString cfg.ipv6 ''
          ip6 saddr @special_purpose_ipv6 drop
          ip6 saddr @bogon_ipv6 drop'';
  v6Icmp = lib.optionalString cfg.ipv6 ''
          # ICMPv6 (ND keeps link-local healthy; errors + rate-limited echo)
          ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
          ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem } accept
          ip6 nexthdr icmpv6 icmpv6 type echo-request limit rate ${L.icmpEcho} accept'';
in
{
  # nftables owns the whole ruleset; the stock high-level firewall stays off.
  networking.firewall.enable = false;

  # ── Security sysctls (pair with the nft ruleset) ───────────────────────────────
  boot.kernel.sysctl = {
    # WireGuard forward path (wg0 -> fabric). Safe: forward chain is default-drop, only wg0.
    "net.ipv4.ip_forward" = 1;

    # SYN-flood resilience (kernel side; the nft layer adds per-source SYN-rate meters).
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_max_syn_backlog" = 4096;
    "net.core.somaxconn" = 4096;

    # No IP source routing (belt-and-braces with the nft `ip option lsrr/ssrr` drops).
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;

    # No ICMP redirects (accept or send) — we are not a router for these hosts.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;

    # ICMP hygiene.
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

    # Log (rate-limited by the kernel) spoofed / unroutable "martian" sources.
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # Reverse-path filter LOOSE (2), not strict — see header note (dummy /32 + ECMP/anycast).
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;

    # Conntrack sizing for a public service under load / attack.
    "net.netfilter.nf_conntrack_max" = 524288;
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
  };

  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet filter {

        # ── static sets ───────────────────────────────────────────────────────────
        # Trusted source networks (local fabric + remote-access VPN) — accepted to ALL ports.
        set trusted_ipv4 {
          type ipv4_addr
          flags interval
          elements = { ${trustedElems} }
        }

        # The public addresses THIS node answers for (own unicast /32 + shared anycast /32).
        set dave_public {
          type ipv4_addr
          elements = { ${davePublicElems} }
        }

        # Known-bad / blackholed sources — dropped FIRST (even for established flows), so an
        # incident-response ban or future auto-banner takes effect immediately. Declared
        # empty; populate by hand (`nft add element inet filter blackhole_v4 { 1.2.3.4 }`),
        # from RTBH tooling (../nfb-ladc-asa01/rtbh-blackhole-design.md), or a later
        # fail2ban/CrowdSec bouncer. `interval` allows CIDR, `timeout` allows auto-expiry.
        # (blackhole_v6 is defined with the other v6 sets below, only when cfg.ipv6 is true.)
        set blackhole_v4 { type ipv4_addr; flags interval, timeout; }

        # Sources authorized (by a knock on tcp/${toString p.knock}) to reach SSH, with a timeout.
        set ssh_clients_v4 {
          type ipv4_addr
          flags timeout
        }

        # RFC 6890 special-purpose / martian ranges — a legitimate internet client never has
        # one of these as its source. Applied ONLY to internet traffic (fabric is accepted
        # first, so its 10.0.0.0/8 source never reaches these drops).
        set special_purpose_ipv4 {
          type ipv4_addr
          flags interval
          elements = {
            0.0.0.0/8,           # "This" network
            10.0.0.0/8,          # Private-use (our fabric — already accepted earlier)
            100.64.0.0/10,       # Shared address space (CGN)
            127.0.0.0/8,         # Loopback
            169.254.0.0/16,      # Link-local
            172.16.0.0/12,       # Private-use
            192.0.0.0/24,        # IETF protocol assignments
            192.0.2.0/24,        # TEST-NET-1
            192.88.99.0/24,      # 6to4 relay anycast
            192.168.0.0/16,      # Private-use
            198.18.0.0/15,       # Benchmarking
            198.51.100.0/24,     # TEST-NET-2
            203.0.113.0/24,      # TEST-NET-3
            224.0.0.0/3          # Multicast + reserved (240/4)
          }
        }
        # Team-Cymru fullbogons — declared EMPTY here and populated at runtime by
        # bogon-refresh.service (weekly timer). Empty = one fewer layer, fail-open, safe.
        set bogon_ipv4 { type ipv4_addr; flags interval; auto-merge; }

        # IPv6 sets (special-purpose + bogon + blackhole) — only when cfg.ipv6 is true.
        ${v6Sets}

        # ── per-source meter sets (SIZED -> bounded memory; fail-open when full) ─────
        set pub_synrate  { type ipv4_addr; size ${toString L.meterSize}; flags dynamic; }  # new-conn rate (web/kafka)
        set pub_conns    { type ipv4_addr; size ${toString L.meterSize}; flags dynamic; }  # concurrent conns (web/kafka)
        set dns_rate     { type ipv4_addr; size ${toString L.meterSize}; flags dynamic; }  # DNS rate (anycast)
        set icmp_echo_rl { type ipv4_addr; size ${toString L.meterSize}; flags dynamic; }  # ping rate
        set ssh_rate     { type ipv4_addr; size 65536;                   flags dynamic; }  # ssh/knock rate

        # ── TCP flag hygiene (port-scan / malformed-flag drops) ───────────────────
        chain tcp-flag-validation {
          tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn|rst|psh|ack|urg) drop   # all flags
          tcp flags & (fin|syn) == (fin|syn) drop                                   # SYN+FIN
          tcp flags & (syn|rst) == (syn|rst) drop                                   # SYN+RST
          tcp flags & (fin|syn|rst|psh|ack|urg) == 0x0 drop                         # NULL scan
          tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|psh|urg) drop               # XMAS scan
        }

        # ── input ─────────────────────────────────────────────────────────────────
        chain input {
          type filter hook input priority 0; policy drop;

          iif "lo" accept

          # IPv6: dropped here when disabled (v4-only network today); see cfg.ipv6.
          ${v6Disabled}

          # TRUSTED SOURCES (local fabric + remote-access VPN) — unconditional, FIRST, all
          # ports. Placed BEFORE the blackhole so a bad ban entry can never lock out mgmt.
          ip saddr @trusted_ipv4 accept

          # KNOWN-BAD — dropped before established-accept, so a ban kills active flows too.
          ip saddr @blackhole_v4 drop
          ${v6Blackhole}

          # Return traffic for anything the node initiated (bogon fetch, DNS, NTP, PMTUD).
          ct state established,related accept
          ct state invalid drop

          # ── invalid / malformed drops (NEW-internet packets only from here) ──
          ip option lsrr exists drop                              # loose source route
          ip option ssrr exists drop                              # strict source route
          ip option rr   exists drop                              # record route (recon)
          tcp flags syn tcp option maxseg size 1-535 drop         # SACK-panic (CVE-2019-11477)
          meta l4proto tcp jump tcp-flag-validation               # XMAS/NULL/impossible combos
          tcp flags & (fin|syn|rst|ack) != syn ct state new drop  # only a bare SYN opens a new flow

          # Anti-spoof / bogon (internet sources only — fabric already accepted above).
          ip saddr @special_purpose_ipv4 drop
          ip saddr @bogon_ipv4 drop
          ${v6AntiSpoof}

          # ── ICMP to the public IPs: echo (per-source rate-limited), PMTUD, errors ──
          ip daddr @dave_public icmp type echo-request add @icmp_echo_rl { ip saddr ${rlIcmp} } drop
          ip daddr @dave_public icmp type echo-request accept
          ip daddr @dave_public icmp type { destination-unreachable, time-exceeded, parameter-problem } accept

          # ── public TCP services (ASA matrix) — PER-SOURCE rate + conn limited ──
          # SYN/new-conn rate per source (blunt floods/scanners):
          ip daddr @dave_public tcp dport { ${toString p.http}, ${toString p.https}, ${toString p.kafka} } ct state new add @pub_synrate { ip saddr ${rlPub} } drop
          # concurrent connections per source (blunt slowloris/exhaustion):
          ip daddr @dave_public tcp dport { ${toString p.http}, ${toString p.https}, ${toString p.kafka} } ct state new add @pub_conns { ip saddr ct count over ${toString L.pubConns} } drop
          ip daddr @dave_public tcp dport { ${toString p.http}, ${toString p.https}, ${toString p.kafka} } ct state new accept

          # ── DNS + iperf2 — anycast .238 ONLY ──
          ip daddr ${cfg.anycast} udp dport ${toString p.dns} add @dns_rate { ip saddr ${rlPub} } drop
          ip daddr ${cfg.anycast} udp dport ${toString p.dns} accept
          ip daddr ${cfg.anycast} tcp dport ${toString p.dns} ct state new add @dns_rate { ip saddr ${rlPub} } drop
          ip daddr ${cfg.anycast} tcp dport ${toString p.dns} ct state new accept
          ip daddr ${cfg.anycast} tcp dport ${toString p.iperfTcp} ct state new accept   # testing, unlimited
          ip daddr ${cfg.anycast} udp dport ${toString p.iperfUdp} accept                # testing, unlimited

          # WireGuard listen — unicast + anycast. Inert until wireguard.nix binds it.
          ip daddr @dave_public udp dport ${toString wg.listenPort} accept

          # ── PORT-KNOCK + SSH ──
          # A new TCP to the knock port (per-source rate-limited to bound set churn)
          # authorizes the source for SSH, then the knock packet is dropped (nothing listens).
          ip daddr @dave_public tcp dport ${toString p.knock} ct state new add @ssh_rate { ip saddr ${rlSsh} } drop
          ip daddr @dave_public tcp dport ${toString p.knock} ct state new update @ssh_clients_v4 { ip saddr timeout ${cfg.sshClientTimeout} } drop
          # SSH from the internet ONLY for a knocked source (fabric SSH accepted far above),
          # itself per-source rate-limited:
          ip saddr @ssh_clients_v4 tcp dport ${toString p.ssh} ct state new add @ssh_rate { ip saddr ${rlSsh} } drop
          ip saddr @ssh_clients_v4 tcp dport ${toString p.ssh} ct state new accept

          ${v6Icmp}

          # Observability: sample what we're about to drop to the public IPs (rate-limited).
          ip daddr @dave_public limit rate 10/minute log prefix "nft-input-drop: " counter

          # (everything else falls through to `policy drop`)
        }

        # ── forward ─────────────────────────────────────────────────────────────────
        chain forward {
          type filter hook forward priority 0; policy drop;
          # Endpoint doesn't forward, EXCEPT the WireGuard path (inert until wg0 exists):
          ct state established,related accept
          iifname "${wg.interface}" accept                 # WG client -> fabric / internet
        }

        # ── output ──────────────────────────────────────────────────────────────────
        chain output {
          type filter hook output priority 0; policy accept;   # node egress unrestricted
        }
      }

      # WireGuard client -> fabric masquerade. SNAT WG-sourced traffic to the node's fabric
      # IP (out bond0.401) so 10.241.10.0/24 reachability needs no fabric/ToR route changes.
      # Only matches the WG tunnel subnet; inert until the tunnel is up.
      table ip nat {
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${wg.tunnelSubnet} oifname "bond0.401" masquerade
        }
      }
    '';
  };
}
