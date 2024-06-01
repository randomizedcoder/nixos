{ config, pkgs, ... }:

{
  # https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html
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
    # enable Enable reuse of TIME-WAIT sockets globally
    "net.ipv4.tcp_tw_reuse" = 1;
    #net.ipv4.tcp_tw_reuse=2
    "net.ipv4.tcp_timestamps" = 1;
    "net.ipv4.tcp_ecn" = 1;
    "net.core.rmem_default" = 26214400;
    "net.core.rmem_max" = 26214400;
    "net.core.wmem_default" = 26214400;
    "net.core.wmem_max" = 26214400;
    #net.core.optmem_max = 20480
    #net.core.rmem_default = 212992
    #net.core.rmem_max = 212992
    #net.core.wmem_default = 212992
    #net.core.wmem_max = 212992
    "net.ipv4.ip_local_port_range" = "1025 65535";
    #net.ipv4.ip_local_port_range ="32768 60999"
  };
}