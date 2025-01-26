{ config, pkgs, ... }:

{
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    networkmanager = {
      enable = true;
      #wifi.powersave = true;
      wifi.powersave = false;
    };
  };

  #networking.hosts = {
    # "172.16.50.216" = ["hp0"];
    # "172.16.40.35" = ["hp1"];
    # "172.16.40.71" = ["hp2"];
  #};
}