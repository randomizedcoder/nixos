#
# /etc/nixos/bogon-refresh.nix  —  identical on every super-* node
#
# Populates the (empty-at-load) `bogon_ipv4` / `bogon_ipv6` nftables sets declared in
# firewall.nix with the Team-Cymru fullbogons lists, and refreshes them weekly.
#
# This one writeShellApplication REPLACES both reference scripts (dcops_combined):
# update-bogons.sh (fetch) + generate-bogons.sh (list-building), collapsed into a single
# runtime fetch -> load. It runs on a weekly timer, at boot, and by hand (`sudo bogon-refresh`).
#
# WHY runtime, not build-time: the reference baked a ~4 MB generated bogons.nix into the
# ruleset and refreshed via `nixos-rebuild`. Here we keep the sets in the ruleset but fill
# them at runtime with `nft -f`, so a refresh is just a timer firing — no 4 MB generated
# file, no rebuild-to-refresh.
#
# FAIL-OPEN / self-preserving: on ANY error — fetch failure, or a truncated/garbage download
# that fails the sanity-count guard, or an nft load error — the script exits 0 WITHOUT
# flushing, so the PREVIOUSLY-LOADED bogons stay in force (the nft transaction is atomic:
# flush + add succeed or fail together). Only on first boot (never yet loaded) or after an
# nft reload flushed the ruleset is the set empty until the next successful run; an empty
# bogon set just means one fewer defense layer — nothing legitimate breaks.
#
# NOTE on `switch`: an nft reload flushes the ruleset, which empties these sets until the
# next timer tick (or a manual `systemctl start bogon-refresh`). That is the fail-open state,
# so it is acceptable; the service also runs once at boot after nftables comes up.
#
{ config, lib, pkgs, ... }:

let
  # Team-Cymru fullbogons. Kept here (not in firewall.nix's cfg) since only this module uses them.
  urlV4 = "https://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt";
  urlV6 = "https://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt";

  bogonRefresh = pkgs.writeShellApplication {
    name = "bogon-refresh";
    runtimeInputs = [ pkgs.curl pkgs.nftables pkgs.coreutils ];
    text = ''
      # Fetch the two lists into a temp dir; fail-open on any error.
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      if ! curl -fsS --max-time 60 -o "$tmp/v4.txt" "${urlV4}"; then
        echo "bogon-refresh: IPv4 fetch failed, leaving bogon_ipv4 unchanged (fail-open)" >&2
        exit 0
      fi
      if ! curl -fsS --max-time 60 -o "$tmp/v6.txt" "${urlV6}"; then
        echo "bogon-refresh: IPv6 fetch failed, leaving bogon_ipv6 unchanged (fail-open)" >&2
        exit 0
      fi

      # Build the element lists with pure-bash parsing (no awk/sed). Skip comments/blanks.
      # Exclude our own space so a stale list can never black-hole us:
      #   - RFC1918 (10/8 covers the 10.241.10.0/24 fabric), 172.16/12, 192.168/16
      #   - our public block 160.72.197.224/28
      elems4=""; n4=0
      while read -r line; do
        line="''${line%%[[:space:]]*}"            # first field only (defensive)
        [[ -z "$line" || "$line" == \#* ]] && continue
        case "$line" in
          10.0.0.0/8|172.16.0.0/12|192.168.0.0/16|160.72.197.224/28) continue ;;
        esac
        elems4+="$line, "; n4=$((n4 + 1))
      done < "$tmp/v4.txt"
      elems4="''${elems4%, }"                      # strip trailing ", "

      elems6=""; n6=0
      while read -r line; do
        line="''${line%%[[:space:]]*}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        elems6+="$line, "; n6=$((n6 + 1))
      done < "$tmp/v6.txt"
      elems6="''${elems6%, }"

      # Sanity guard: the real lists are thousands of entries. A tiny count means a
      # truncated / garbage download that still returned HTTP 200 — treat it as a failure
      # and KEEP the existing sets (do not flush) so the current filter stays in force.
      if [[ "$n4" -lt 500 || "$n6" -lt 1000 ]]; then
        echo "bogon-refresh: implausibly small list (v4=$n4 v6=$n6) — keeping existing sets (fail-open)" >&2
        exit 0
      fi

      # Assemble one atomic nft transaction: flush each set, then re-add its elements.
      nft_file="$tmp/bogons.nft"
      {
        echo "flush set inet filter bogon_ipv4"
        [[ -n "$elems4" ]] && echo "add element inet filter bogon_ipv4 { $elems4 }"
        echo "flush set inet filter bogon_ipv6"
        [[ -n "$elems6" ]] && echo "add element inet filter bogon_ipv6 { $elems6 }"
      } > "$nft_file"

      if nft -f "$nft_file"; then
        echo "bogon-refresh: loaded bogons (v4 + v6)"
      else
        echo "bogon-refresh: nft load failed (is nftables up?) — sets left as-is" >&2
        exit 0
      fi
    '';
  };
in
{
  # Also expose it as a command so it can be run by hand (`sudo bogon-refresh`) — the
  # manual-update affordance the reference's update-bogons.sh had.
  environment.systemPackages = [ bogonRefresh ];

  systemd.services.bogon-refresh = {
    description = "Populate nftables bogon_ipv4/ipv6 sets from Team-Cymru fullbogons";
    # The sets live in the firewall ruleset, and the fetch needs the network up.
    after = [ "nftables.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "nftables.service" ];
    # Run once at boot after the firewall is up; the timer keeps it fresh thereafter.
    wantedBy = [ "multi-user.target" ];
    # If nftables is restarted (re-created the empty sets), refill them.
    partOf = [ "nftables.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe bogonRefresh;
    };
  };

  systemd.timers.bogon-refresh = {
    description = "Weekly refresh of the nftables bogon sets";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;          # catch up if the node was off when it was due
      RandomizedDelaySec = "1h";  # avoid all nodes hitting Team-Cymru at the same instant
    };
  };
}
