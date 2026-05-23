{ config, pkgs, ... }:

{
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking = {
    networkmanager = {
      enable = true;
      # Laptop: enable wifi powersave to extend battery life.
      wifi.powersave = true;
    };
  };

  #networking.hosts = {
    # "172.16.50.216" = ["hp0"];
    # "172.16.40.35" = ["hp1"];
    # "172.16.40.71" = ["hp2"];
  #};
}