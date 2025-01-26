{ config, pkgs, ... }:

{
  networking.wireless = {
    enable = true;  # Enables wireless support via wpa_supplicant.
    #environmentFile = "/home/das/wireless.env";
    networks."devices".psk = "performance";
    #networks."devices".psk = "@PSK_DEVICES@";
    extraConfig = "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel";
    # output ends up in /run/wpa_supplicant/wpa_supplicant.conf
  };
  # https://linux.die.net/man/5/wpa_supplicant.conf
  # https://nixos.wiki/wiki/Wpa_supplicant
  # https://nixos.org/manual/nixos/stable/options#opt-networking.wireless.environmentFile
  # https://blog.stigok.com/2021/05/04/getting-wpa-cli-to-work-in-nixos.html
}