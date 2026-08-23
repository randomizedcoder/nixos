{ config, pkgs, lib, ... }:
# mtr-exporter (github.com/mgumz/mtr-exporter, packaged in nixpkgs) — runs `mtr` on a
# schedule and exports per-hop path metrics to Prometheus. Unlike static Smokeping hops,
# it re-traces every run, so it follows ECMP/path changes automatically. We monitor the
# upstream path to Google (and Cloudflare as a second reference) over BOTH IPv4 and IPv6.
#
# Metrics (per hop): mtr_report_{loss,avg,best,wrst,last,stdev,snt} with labels
# dst / host (the hop) / hop (first|intermediate|last) / path_id. Scraped by the
# prometheus "mtr" job; visualised by dashboards/mtr-path.json. Bound to localhost only.
let
  # jobs file syntax:  <label> -- <schedule> -- <mtr-flags... target>
  #   -4/-6 force address family; -c N = report cycles per run; hop names left resolved
  #   (no -n) so Charter/Google router names show up. These four services all block ICMP
  #   echo to the destination, so we probe with TCP to 443 (-T -P 443): intermediate hops
  #   still answer via ICMP TTL-exceeded, and the destination answers the TCP handshake —
  #   giving both full-path visibility AND real end-to-end reachability. Both IPv4 & IPv6.
  #
  # SCHEDULING — why staggered cron instead of "@every 60s":
  #   With all 8 jobs on @every 60s they fired simultaneously, so up to 8 (often more,
  #   since a ~16s run overlaps the next tick) mtr processes ran at once. In TCP mode the
  #   raw sockets of concurrent SAME-FAMILY probes capture each other's replies, so e.g.
  #   Yahoo routers showed up mislabelled on the Google trace — the per-hop data for the
  #   early/middle hops was scrambled (verified: v4<->v6 never cross-contaminate because
  #   they use separate AF_INET/AF_INET6 raw sockets; only v4-with-v4 / v6-with-v6 do).
  #   Fix: run exactly one destination's v4+v6 pair per minute on a 4-minute cron cycle
  #   (0/1/2/3 mod 4). At any instant at most one v4 mtr and one v6 mtr run — different
  #   families, so no collision. 4 min is the tightest cycle that isolates 4 destinations
  #   AND stays under Prometheus's 5-min staleness window (an 8-min full-serialize would
  #   leave gaps between samples). Each path is now probed every 4 min instead of 60s.
  jobsFile = pkgs.writeText "mtr-exporter.jobs" ''
    google-v4   -- 0-59/4 * * * * -- -4 -T -P 443 -c 10 google.com
    google-v6   -- 0-59/4 * * * * -- -6 -T -P 443 -c 10 google.com
    facebook-v4 -- 1-59/4 * * * * -- -4 -T -P 443 -c 10 facebook.com
    facebook-v6 -- 1-59/4 * * * * -- -6 -T -P 443 -c 10 facebook.com
    ibm-v4      -- 2-59/4 * * * * -- -4 -T -P 443 -c 10 ibm.com
    ibm-v6      -- 2-59/4 * * * * -- -6 -T -P 443 -c 10 ibm.com
    yahoo-v4    -- 3-59/4 * * * * -- -4 -T -P 443 -c 10 yahoo.com
    yahoo-v6    -- 3-59/4 * * * * -- -6 -T -P 443 -c 10 yahoo.com
  '';
in
{
  systemd.services.mtr-exporter = {
    description = "mtr-exporter — per-hop path metrics (IPv4+IPv6) to Prometheus";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # mtr calls its mtr-packet helper by name — keep it on PATH.
    path = [ pkgs.mtr ];
    serviceConfig = {
      ExecStart = "${pkgs.mtr-exporter}/bin/mtr-exporter -bind 127.0.0.1:9142 -mtr ${pkgs.mtr}/bin/mtr -jobs ${jobsFile}";
      DynamicUser = true;
      # mtr needs raw sockets for ICMP probing / receiving TTL-exceeded.
      AmbientCapabilities = [ "CAP_NET_RAW" ];
      CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
