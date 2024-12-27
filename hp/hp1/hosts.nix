{ config, pkgs, ... }:

{
  networking.hosts = {
    "172.16.40.198" = ["hp0" "hp0eth"]; # adi's room
    "172.16.40.152" = ["hp0wifi"];
    "172.16.40.142" = ["hp1" "hp1eth"];
    "172.16.40.212" = ["hp2" "hp2eth"];
    "172.16.40.146" = ["hp3" "hp3eth"]; # savi's room
    "172.16.40.130" = ["hp3wifi"];
    "172.16.50.232" = ["hp4" "hp4eth"]; # rack
    "172.16.40.70"  = ["hp5" "hp5eth"];
    "10.43.130.25"  = ["redpanda-0" "seed_0" ];
  };
}