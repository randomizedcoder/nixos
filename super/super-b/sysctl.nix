#
# /etc/nixos/sysctl.nix  —  identical on every super-* node
#
# Kernel network tuning, synced from ~/nixos/desktop/l/sysctl.nix (the workstation's
# curated TCP-stack tweaks). No external module dependencies: sch_cake and cubic are
# both in-tree in the NixOS default kernel (auto-loaded when referenced), so this drops
# in cleanly on the stock super-* kernels. Keep in sync with desktop/l/sysctl.nix.
#
# References:
#   https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html
#   https://www.l4sgear.com/
#
{ config, pkgs, ... }:

{
  boot.kernel.sysctl = {
    # detect dead connections more quickly
    "net.ipv4.tcp_keepalive_intvl" = 30;
    #net.ipv4.tcp_keepalive_intvl = 75
    "net.ipv4.tcp_keepalive_probes" = 4;
    #net.ipv4.tcp_keepalive_probes = 9
    "net.ipv4.tcp_keepalive_time" = 120;
    #net.ipv4.tcp_keepalive_time = 7200
    # 30 * 4 = 120 seconds. / 60 = 2 minutes
    # default: 75 seconds * 9 = 675 seconds. /60 = 11.25 minutes
    "net.ipv4.tcp_rmem" = "4096	1000000	16000000";
    "net.ipv4.tcp_wmem" = "4096	1000000	16000000";
    #net.ipv4.tcp_rmem = 4096       131072  6291456
    #net.ipv4.tcp_wmem = 4096       16384   4194304
    "net.ipv6.tcp_rmem" = "4096	1000000	16000000";
    "net.ipv6.tcp_wmem" = "4096	1000000	16000000";
    # https://github.com/torvalds/linux/blob/master/Documentation/networking/ip-sysctl.rst?plain=1#L1042
    # https://lwn.net/Articles/560082/
    "net.ipv4.tcp_notsent_lowat" = "131072";
    #net.ipv4.tcp_notsent_lowat = 4294967295
    # enable Enable reuse of TIME-WAIT sockets globally
    "net.ipv4.tcp_tw_reuse" = 1;
    #net.ipv4.tcp_tw_reuse=2
    "net.ipv4.tcp_timestamps" = 1;
    "net.ipv4.tcp_ecn" = 1;
    # NOTE: diverges from desktop/l (which uses "cake"). cake's shaper is a single
    # serialized stage — great as THE bottleneck qdisc on a constrained uplink, but on a
    # line-rate multiqueue 10G server NIC there's nothing to shape and its per-queue
    # instances just add lock/CPU overhead. fq_codel under mq gives one light instance per
    # HW queue (scales across cores) with per-flow fairness + CoDel AQM — right for a server
    # fielding many internet clients. (Consider "fq" if we move to BBR, for pacing offload.)
    "net.core.default_qdisc" = "fq_codel";
    "net.ipv4.tcp_congestion_control" = "cubic";
    #net.ipv4.tcp_congestion_control=bbr
    "net.core.rmem_default" = 26214400;
    "net.core.rmem_max" = 26214400;
    "net.core.wmem_default" = 26214400;
    "net.core.wmem_max" = 26214400;
    #net.core.optmem_max = 20480
    #net.core.rmem_default = 212992
    #net.core.rmem_max = 212992
    #net.core.wmem_default = 212992
    #net.core.wmem_max = 212992
    "net.ipv4.ip_local_port_range" = "1026 65535";
    #net.ipv4.ip_local_port_range ="32768 60999"
    #
    #net.ipv4.inet_peer_maxttl = 600
    #net.ipv4.inet_peer_minttl = 120
    #net.ipv4.ip_default_ttl = 64
    # we DO want to save the slow start in the route cache
    "net.ipv4.tcp_no_ssthresh_metrics_save" = 0;
    #net.ipv4.tcp_no_ssthresh_metrics_save = 1
    "net.ipv4.tcp_reflect_tos" = 1;
    #net.ipv4.tcp_reflect_tos = 0
    "net.ipv4.tcp_rto_min_us" = 50000; #50ms
    #net.ipv4.tcp_rto_min_us = 200000 #200ms

    # TCP optimizations for high performance
    "net.ipv4.tcp_slow_start_after_idle" = 0;      # Disable slow start after idle
    "net.ipv4.tcp_fastopen" = 3;                   # Enable TCP Fast Open

    "net.ipv4.tcp_window_scaling" = 1;
    "net.ipv4.tcp_sack" = 1;
    "net.ipv4.tcp_fack" = 1;
    "net.ipv4.tcp_fin_timeout" = 30;
  };
}
