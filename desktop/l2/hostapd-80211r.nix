#
# hostapd-80211r.nix
#

{ pkgs ? import <nixpkgs> {} }:

pkgs.hostapd.override {
  extraConfig = ''
    CONFIG_DRIVER_NL80211=y
    CONFIG_IEEE80211R=y
    CONFIG_IEEE80211W=y
    CONFIG_IEEE80211N=y
    CONFIG_IEEE80211AC=y
    CONFIG_IEEE80211AX=y
    CONFIG_ACS=y
    CONFIG_SAE=y
    CONFIG_FULL_DYNAMIC_VLAN=y
    CONFIG_VLAN_NETLINK=y
    CONFIG_RADIUS_SERVER=y
    CONFIG_HS20=y
    CONFIG_WNM=y
    CONFIG_MBO=y
    CONFIG_FST=y
    CONFIG_FST_TEST=y
    CONFIG_CTRL_IFACE=y
  '';
}
