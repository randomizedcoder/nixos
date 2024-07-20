{ pkgs ? import <nixpkgs> { }
, pkgsLinux ? import <nixpkgs> { system = "x86_64-linux"; }
}:

pkgs.dockerTools.buildImage {
  name = "ch-docker";
  config = {
    Cmd = [ "${pkgs.clickhouse}/usr/bin/clickhouse-server" ];
  };
}
