{ config, pkgs, ... }:

{
  networking.hosts = {

    # These entires are added automagically by nixos
    #"127.0.0.1" = [ "localhost" ];
    #"::1" = [ "localhost" ];
    #"127.0.0.2" = [ "l" ];

    "172.16.40.198"   = [ "hp0" "hp0eth" ]; # adi's room
    "172.16.40.141"   = [ "hp0wifi" ];
    "172.16.40.142"   = [ "hp1" "hp1eth" ];
    "172.16.40.212"   = [ "hp2" "hp2eth" ];
    "172.16.40.146"   = [ "hp3" "hp3eth" ]; # savi's room
    "172.16.40.130"   = [ "hp3wifi" ];
    "172.16.50.232"   = [ "hp4" "hp4eth" ]; # rack
    "172.16.40.72"    = [ "hp5" "hp5eth" ];
    "172.16.40.122"   = [ "pi5-1" "pi5-1-eth" ];
    "172.16.40.62"    = [ "chromebox3" "chromebox3-eth" ];
    "172.16.50.219"   = [ "l" ];
    "172.16.40.46"    = [ "l2" ];
    "172.16.50.74"    = [ "t14" ];
    "172.16.40.185"   = [ "nfbQotom" ];
  };
}