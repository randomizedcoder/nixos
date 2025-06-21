#
# hostapd.nix
#

{ config, pkgs, ... }:

let
  interface1 = "wlp35s0"; # e.g. 2.4GHz channel 6
  interface2 = "wlp65s0"; # e.g. 5GHz channel 100
  interface3 = "wlp70s0"; # e.g. 5GHz channel 149

  commonHostapdSettings = ''
    ssid=myssid
    wpa=2
    wpa_key_mgmt=SAE
    rsn_pairwise=CCMP
    sae_require_mfp=1
    ieee80211w=2
    ieee80211n=1
    ieee80211ac=1
    ieee80211ax=1
    wmm_enabled=1

    # WMM tuning for Best Effort (AC_BE)
    wmm_ac_be_aifs=1
    wmm_ac_be_cwmin=4
    wmm_ac_be_cwmax=4
    wmm_ac_be_txop_limit=32
    wmm_ac_be_acm=0

    # 802.11r (Fast BSS Transition)
    ieee80211r=1
    mobility_domain=4f57
    ft_over_ds=1
    ft_psk_generate_local=1
    nas_identifier=myssid-ap
  '';
in
{
  services.hostapd = {
    enable = true;
    radios = {
      "${interface1}" = {
        config = pkgs.writeText "hostapd-1.conf" (''
          interface=${interface1}
          hw_mode=g
          channel=6
          ${commonHostapdSettings}
        '');
      };
      "${interface2}" = {
        config = pkgs.writeText "hostapd-2.conf" (''
          interface=${interface2}
          hw_mode=a
          channel=100
          ${commonHostapdSettings}
        '');
      };
      "${interface3}" = {
        config = pkgs.writeText "hostapd-3.conf" (''
          interface=${interface3}
          hw_mode=a
          channel=149
          ${commonHostapdSettings}
        '');
      };
    };
  };

  # Disable DHCP on all interfaces, use static IP or bridge later
  networking.interfaces.${interface1}.useDHCP = false;
  networking.interfaces.${interface2}.useDHCP = false;
  networking.interfaces.${interface3}.useDHCP = false;

  networking.interfaces.${interface1}.ipv4.addresses = [ { address = "192.168.30.1"; prefixLength = 24; } ];
  networking.interfaces.${interface2}.ipv4.addresses = [ { address = "192.168.31.1"; prefixLength = 24; } ];
  networking.interfaces.${interface3}.ipv4.addresses = [ { address = "192.168.32.1"; prefixLength = 24; } ];

  networking.firewall.enable = true;
  networking.nat.enable = true;
  networking.nat.externalInterface = "enp1s0";
}
