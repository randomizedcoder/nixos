{ config, pkgs, lib, ... }:
# Persistent-connection HTTP latency monitor.
#
# WHY: Smokeping's Curl probe (and blackbox) open a FRESH TCP+TLS connection for every
# request, so they always pay ~2-3 round-trips + crypto (~50ms to a ~10ms-away edge) and
# never measure the actual request. That made Google look like it "takes 120ms" when a
# warm request to its edge is ~9ms. This probe reuses one connection for a burst of
# requests and reports the WARM request latency (2nd+ request, no new connect/TLS) — the
# number that reflects real repeated page loads — for each site over BOTH IPv4 and IPv6.
#
# Metrics (served by node-exporter's textfile collector on :9000, scraped by the "node"
# job, so no extra scrape config):
#   http_persistent_warm_seconds{host,family}        median warm request time (the headline)
#   http_persistent_setup_seconds{host,family}       cold TCP+TLS setup cost (time_appconnect)
#   http_persistent_cold_total_seconds{host,family}  full first-request time (setup + request)
#   http_persistent_up{host,family}                  1 = probe succeeded, 0 = failed
let
  textfileDir = "/var/lib/node-exporter-textfile";
  hosts = [ "google.com" "facebook.com" "ibm.com" "yahoo.com" ];

  probe = pkgs.writeShellApplication {
    name = "http-persistent-probe";
    runtimeInputs = [ pkgs.curl pkgs.coreutils pkgs.gawk ];
    text = ''
      set -u
      OUT="${textfileDir}/http_persistent.prom"
      # Fixed temp name (not $$-suffixed): the timer runs this oneshot sequentially, so a
      # single reusable temp can't collide, and a failed run leaves at most one stale
      # .tmp (ignored by the collector, which only reads *.prom) instead of piling up.
      TMP="$OUT.tmp"
      # Clean up any orphaned PID-suffixed temps (from the pre-gawk-fix failed runs).
      rm -f "$OUT".[0-9]*
      : > "$TMP"
      {
        echo "# HELP http_persistent_warm_seconds Median warm (reused-connection) HTTP request time."
        echo "# TYPE http_persistent_warm_seconds gauge"
        echo "# HELP http_persistent_setup_seconds Cold TCP+TLS connection setup time (time_appconnect)."
        echo "# TYPE http_persistent_setup_seconds gauge"
        echo "# HELP http_persistent_cold_total_seconds Full first-request time including connection setup."
        echo "# TYPE http_persistent_cold_total_seconds gauge"
        echo "# HELP http_persistent_up Whether the persistent HTTP probe succeeded."
        echo "# TYPE http_persistent_up gauge"
      } >> "$TMP"

      for host in ${lib.concatStringsSep " " hosts}; do
        for fam in 4 6; do
          if [ "$fam" = 4 ]; then family=ipv4; else family=ipv6; fi
          # Probe www.<host> — returns 200 with keep-alive on all four sites (the apex
          # names 301 but also keep-alive; www gives a real 200 content fetch).
          url="https://www.$host/robots.txt"
          # 6 requests on ONE connection: req1 = cold (opens conn), req2-6 = warm (reused).
          # One -o /dev/null PER url is required: with a single -o, curl sends the 2nd..Nth
          # response bodies to stdout and corrupts the -w timing lines.
          oargs=(); for _ in 1 2 3 4 5 6; do oargs+=(-o /dev/null "$url"); done
          # -w prints one line per request: num_connects appconnect starttransfer total
          data=$(curl "-$fam" -sS --compressed --http2 --max-time 10 \
                   -w '%{num_connects} %{time_appconnect} %{time_starttransfer} %{time_total}\n' \
                   "''${oargs[@]}" 2>/dev/null || true)

          if [ -z "$data" ]; then
            echo "http_persistent_up{host=\"$host\",family=\"$family\"} 0" >> "$TMP"
            continue
          fi

          # cold = the line that opened the connection (num_connects >= 1)
          setup=$(echo "$data"  | awk '$1>=1{print $2; exit}')
          cold=$(echo "$data"   | awk '$1>=1{print $4; exit}')
          # warm = median time_starttransfer over the reused-connection requests (num_connects==0)
          warm=$(echo "$data"   | awk '$1==0{print $3}' | sort -n | awk '{a[NR]=$1} END{if(NR)print (NR%2)?a[int(NR/2)+1]:(a[NR/2]+a[NR/2+1])/2}')

          echo "http_persistent_up{host=\"$host\",family=\"$family\"} 1" >> "$TMP"
          [ -n "$setup" ] && echo "http_persistent_setup_seconds{host=\"$host\",family=\"$family\"} $setup" >> "$TMP"
          [ -n "$cold" ]  && echo "http_persistent_cold_total_seconds{host=\"$host\",family=\"$family\"} $cold" >> "$TMP"
          [ -n "$warm" ]  && echo "http_persistent_warm_seconds{host=\"$host\",family=\"$family\"} $warm" >> "$TMP"
        done
      done

      # atomic replace so node-exporter never reads a partial file
      mv -f "$TMP" "$OUT"
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 http-persistent http-persistent - -"
  ];

  users.users.http-persistent = {
    isSystemUser = true;
    group = "http-persistent";
    description = "Persistent-connection HTTP probe";
  };
  users.groups.http-persistent = { };

  systemd.services.http-persistent-probe = {
    description = "Persistent-connection HTTP latency probe (v4+v6, warm request time)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "http-persistent";
      Group = "http-persistent";
      ExecStart = "${probe}/bin/http-persistent-probe";
      # hardening — it only needs outbound TCP + DNS
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ textfileDir ];
    };
  };

  systemd.timers.http-persistent-probe = {
    description = "Run the persistent-connection HTTP probe every 30s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
      AccuracySec = "1s";
    };
  };
}
