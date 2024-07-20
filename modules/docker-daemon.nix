
{ config, pkgs, ... }:

{
  # https://nixos.wiki/wiki/Docker
  # https://search.nixos.org/options?from=0&size=50&sort=alpha_asc&query=virtualisation.docker
  # https://search.nixos.org/options?channel=24.05&show=virtualisation.docker.extraOptions&from=0&size=50&sort=alpha_asc&type=packages&query=virtualisation.docker
  # https://github.com/NixOS/nixpkgs/issues/68349
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    data-root = "/home/das/docker/";
    userland-proxy = false;
    experimental = true;
    ipv6 = true;
    fixed-cidr-v6 = "fd00::/80";
    metrics-addr = "0.0.0.0:9323";
    # log-driver = "json-file";
    # log-opts.max-size = "10m";
    # log-opts.max-file = "10";
  };
  #this doesn't work
  #virtualisation.docker.daemon.settings.log-opts.max-size = "10m";
  # https://docs.docker.com/reference/cli/dockerd/
  #virtualisation.docker.extraOptions = "--userland-proxy=false";
  #virtualisation.docker.extraOptions = "--log-opt=max-size=10m";
  #virtualisation.docker.extraOptions = "--ipv6";
}