#
# sysctl.nix
#
{ config, pkgs, ... }:

{
  # https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html
  # https://www.l4sgear.com/
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
    # https://github.com/torvalds/linux/blob/master/Documentation/networking/ip-sysctl.rst?plain=1#L1042
    # https://lwn.net/Articles/560082/
    "net.ipv4.tcp_notsent_lowat" = "131072";
    #net.ipv4.tcp_notsent_lowat = 4294967295
    # enable Enable reuse of TIME-WAIT sockets globally
    "net.ipv4.tcp_tw_reuse" = 1;
    #net.ipv4.tcp_tw_reuse=2
    "net.ipv4.tcp_timestamps" = 1;
    "net.ipv4.tcp_ecn" = 1;
    "net.core.default_qdisc" = "cake";
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
    #not using 1025 because the kernel complains about wanting different parity
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

    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    # Additional network optimizations for WiFi access point
    # TCP optimizations
    "net.ipv4.tcp_window_scaling" = 1;
    "net.ipv4.tcp_sack" = 1;
    "net.ipv4.tcp_fack" = 1;
    "net.ipv4.tcp_fin_timeout" = 30;

    # Increase connection tracking table size for multiple WiFi clients
    "net.netfilter.nf_conntrack_max" = 262144;
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;

    # Network interface optimizations
    "net.core.netdev_max_backlog" = 5000;
    "net.core.netdev_budget" = 600; # default 300
    "net.core.netdev_budget_usecs" = 8000; #default 2000, increasing to 8ms

    # IPv6 optimizations
    "net.ipv6.tcp_rmem" = "4096	1000000	16000000";
    "net.ipv6.tcp_wmem" = "4096	1000000	16000000";

    # Additional network stack optimizations
    "net.core.netdev_tstamp_prequeue" = 0;    # Disable prequeue timestamping
    "net.core.rps_sock_flow_entries" = 32768; # RPS flow entries

    # TCP optimizations for high performance
    "net.ipv4.tcp_slow_start_after_idle" = 0;      # Disable slow start after idle
    "net.ipv4.tcp_fastopen" = 3;                   # Enable TCP Fast Open

    # IPv6 parameters
    "net.ipv6.conf.all.accept_ra" = 2;             # Accept RA
    "net.ipv6.conf.default.accept_ra" = 2;         # Accept RA
    "net.ipv6.conf.all.autoconf" = 1;              # Enable autoconf
    "net.ipv6.conf.default.autoconf" = 1;          # Enable autoconf

    # Connection tracking optimizations
    "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;
    "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 60;
    "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 120;
    "net.netfilter.nf_conntrack_udp_timeout" = 30;
    "net.netfilter.nf_conntrack_udp_timeout_stream" = 180;

    # Memory management optimizations
    "vm.swappiness" = 1;                           # Minimize swapping
    "vm.dirty_ratio" = 15;                         # Dirty page ratio
    "vm.dirty_background_ratio" = 5;               # Background dirty ratio
    "vm.dirty_writeback_centisecs" = 500;          # Writeback interval
    "vm.dirty_expire_centisecs" = 3000;            # Expire interval
    "vm.vfs_cache_pressure" = 50;                  # Cache pressure
    "vm.overcommit_memory" = 1;                    # Allow overcommit

    # NUMA optimization
    "vm.numa_balancing" = 0;                       # Disable NUMA balancing

    # Process limits
    "kernel.pid_max" = 65536;                      # Increase PID limit
    "kernel.threads-max" = 2097152;                # Increase thread limit
    "kernel.sched_rt_runtime_us" = -1;             # Disable RT throttling
    "kernel.sched_rt_period_us" = 1000000;         # RT period

    # Security (minimal impact)
    "kernel.kptr_restrict" = 0;                    # Allow kptr access
    "kernel.perf_event_paranoid" = 0;              # Allow perf events
  };
}