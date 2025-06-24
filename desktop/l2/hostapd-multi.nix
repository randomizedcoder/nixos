#
# hostapd-multi.nix
#

{ config, lib, pkgs, ... }:

{
  services.hostapd.enable = true;

  services.hostapd.radios = {
    wlp35s0 = {
      interface = "wlp35s0";
      ssid = "myssid";
      countryCode = "US";
      channel = 52; # 5.26 GHz
      hwMode = "a";
      bridge = "br0";
      auth.algo = "open";
      wpa.enable = true;
      wpa.passphrase = "strongpassword";
      wpa.keyMgmt = [ "WPA-PSK" ];
    };

    wlp65s0 = {
      interface = "wlp65s0";
      ssid = "myssid";
      countryCode = "US";
      channel = 56; # 5.28 GHz
      hwMode = "a";
      bridge = "br0";
      auth.algo = "open";
      wpa.enable = true;
      wpa.passphrase = "strongpassword";
      wpa.keyMgmt = [ "WPA-PSK" ];
    };

    wlp66s0 = {
      interface = "wlp66s0";
      ssid = "myssid";
      countryCode = "US";
      channel = 60; # 5.30 GHz
      hwMode = "a";
      bridge = "br0";
      auth.algo = "open";
      wpa.enable = true;
      wpa.passphrase = "strongpassword";
      wpa.keyMgmt = [ "WPA-PSK" ];
    };

    wlp97s0 = {
      interface = "wlp97s0";
      ssid = "myssid";
      countryCode = "US";
      channel = 64; # 5.32 GHz
      hwMode = "a";
      bridge = "br0";
      auth.algo = "open";
      wpa.enable = true;
      wpa.passphrase = "strongpassword";
      wpa.keyMgmt = [ "WPA-PSK" ];
    };
  };

  networking = {
    networkmanager.enable = false;
    useDHCP = false;

    bridges.br0.interfaces = [ ];

    interfaces."br0" = {
      ipv4.addresses = [{
        address = "192.168.1.1";
        prefixLength = 24;
      }];
      ipv6.addresses = [{
        address = "fd00::1";
        prefixLength = 64;
      }];
    };

    interfaces."enp1s0".useDHCP = true;

    nat = {
      enable = true;
      externalInterface = "enp1s0";
      internalInterfaces = [ "br0" ];
    };
  };
}
