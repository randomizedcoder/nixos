let
  pkgs = import <nixpkgs> {};
in pkgs.dockerTools.buildImage {
  name = "memcached";
  tag = "latest";
  config.User = "1000";
  config.Entrypoing = [ "${pkgs.memcached}/bin/memcached" ];
}