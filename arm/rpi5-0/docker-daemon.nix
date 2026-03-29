
{ config, pkgs, ... }:

{
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    data-root = "/home/das/docker/";
    userland-proxy = false;
    experimental = true;
    ipv6 = true;
    fixed-cidr-v6 = "fd00::/80";
    metrics-addr = "0.0.0.0:9323";
  };
}
