# nordlayer-lan-bypass.nix
#
# Keeps LAN traffic working while the nordlayer daemon is connected.
# Nordlayer enforces VPN-only egress by two independent mechanisms:
#
#   1. Firewall kill-switch:
#        table inet nordlayer { chain input/output { policy drop; ... } }
#      with one generic accept: `meta mark 0x000133a8 accept`.
#
#   2. Policy routing:
#        ip rule (priorities NN/NN+1):
#          lookup main suppress_prefixlength 0 suppress_ifgroup 78760
#          not from all fwmark 0x133a8 lookup 78760
#        ip route table 78760: default dev nlx0
#      Nordlayer drops the LAN interface (wlp114s0f0 on d, …) into ifgroup
#      78760, so the suppress rule hides the LAN `/24` and `default` from
#      `main`. Unmarked traffic falls through to the next rule and is sent
#      via nlx0 — even when the destination is a LAN host. Nordlayer
#      MONITORS user-added `ip rule` entries and reinserts its own rules
#      below them on the fly (we initially saw 32764/32765; after we added
#      rules at 50/51, nordlayer moved itself to 48/49). So competing on
#      `ip rule` priority is a losing arms race.
#
# Fix without touching `ip rule` at all:
#   Use a `type route` base chain in nftables OUTPUT. `type route` triggers
#   the kernel's "reroute after netfilter" path (ip_route_me_harder) when
#   the packet's mark/src/dst/tos changes inside the chain. Concretely:
#
#     1. Local process emits packet → initial route lookup picks nlx0
#        (no mark yet → `not fwmark` rule matches → lookup table 78760).
#     2. Our `type route` chain at OUTPUT mangle priority sets the mark.
#     3. Kernel re-routes because the mark changed → `not fwmark` rule no
#        longer matches → falls through to `lookup main` (no suppression
#        on that rule) → finds 172.16.50.0/24 dev wlp114s0f0.
#     4. nordlayer's filter chain runs, sees the mark, accepts.
#
#   No `ip rule` plumbing required; survives nordlayer's rule shuffling.
#
# INPUT side uses `type filter` (no reroute needed — packet has already
# arrived; we only need nordlayer's input filter to accept it on the mark).
#
# Brittle to upstream changes:
#   The mark value (0x000133a8 = 78760) is reverse-engineered from
#   `nft list table inet nordlayer` and the `not fwmark 0x133a8` ip rule.
#   If NordLayer ever rotates it, this bypass silently stops working —
#   re-check both and update `acceptMark`.
#
# IPv6:
#   Not handled. Nordlayer's first rule is `meta nfproto ipv6 drop`, which
#   fires before any mark check; there is no way to bypass it from outside
#   the chain. IPv6 LAN traffic stays blocked while the VPN is up.

{ pkgs, lib, ... }:

let
  # See note above on brittleness.
  acceptMark = "0x000133a8";

  # LAN CIDRs to keep reachable while the VPN is up. Edit per-host.
  lanRanges = [
    "172.16.0.0/12"
    "192.168.0.0/16"
  ];

  ranges = lib.concatStringsSep ", " lanRanges;

  nft = "${pkgs.nftables}/bin/nft";
in
{
  systemd.services.nordlayer-lan-bypass = {
    description = "Mark LAN traffic so nordlayer's killswitch + policy routing pass it";
    after = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nordlayer-lan-bypass-up" ''
        set -e

        ${nft} -f - <<'EOF'
        table inet nordlayer-lan-bypass {}
        delete table inet nordlayer-lan-bypass
        table inet nordlayer-lan-bypass {
          # INPUT side: filter is enough — we only need to influence
          # nordlayer's filter verdict, not routing.
          chain pre-input {
            type filter hook input priority mangle;
            ip saddr { ${ranges} } meta mark set ${acceptMark} comment "bypass nordlayer killswitch"
          }

          # OUTPUT side: MUST be `type route` so the kernel re-routes the
          # packet after the mark is set; otherwise the initial (unmarked)
          # routing decision sends LAN traffic into the VPN tunnel.
          chain pre-output {
            type route hook output priority mangle;
            ip daddr { ${ranges} } meta mark set ${acceptMark} comment "bypass nordlayer killswitch + force reroute"
          }
        }
        EOF
      '';
      ExecStop = "${nft} delete table inet nordlayer-lan-bypass 2>/dev/null || true";
    };
  };
}
