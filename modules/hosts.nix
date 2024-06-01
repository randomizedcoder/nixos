{ config, pkgs, ... }:

{
  networking.hosts = {
    "172.16.40.198" = ["hp0eth"];
    "172.16.40.152" = ["hp0wifi"];
    "172.16.40.146" = ["hp3eth"];
    "172.16.40.130" = ["hp3wifi"];
  };
}