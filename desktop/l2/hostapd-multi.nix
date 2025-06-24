#
# hostapd-multi.nix
#

{ config, lib, pkgs, ... }:

{
  services.hostapd.enable = true;

  services.hostapd.radios = {
    wlp35s0 = {
      countryCode = "US";
      band = "5g";
      channel = 52;

      networks.wlp35s0 = {
        ssid = "myssid";
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            { password = "strongpassword"; }
          ];
        };
        settings = {
          bridge = "br0";
          ieee80211w = 2;
        };
      };
    };

    wlp65s0 = {
      countryCode = "US";
      band = "5g";
      channel = 56;

      networks.wlp65s0 = {
        ssid = "myssid";
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            { password = "strongpassword"; }
          ];
        };
        settings = {
          bridge = "br0";
          ieee80211w = 2;
        };
      };
    };

    wlp66s0 = {
      countryCode = "US";
      band = "5g";
      channel = 60;

      networks.wlp66s0 = {
        ssid = "myssid";
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            { password = "strongpassword"; }
          ];
        };
        settings = {
          bridge = "br0";
          ieee80211w = 2;
        };
      };
    };

    wlp97s0 = {
      countryCode = "US";
      band = "5g";
      channel = 64;

      networks.wlp97s0 = {
        ssid = "myssid";
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            { password = "strongpassword"; }
          ];
        };
        settings = {
          bridge = "br0";
          ieee80211w = 2;
        };
      };
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

# end