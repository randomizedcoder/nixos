#
# hostapd.nix
#

#
# NOT using service.hostapd, because it has limited configuration capabilities
# https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/hostapd.nix
#
# Using custom systemd services to run hostapd per interface
#
# systemctl status hostapd-wlp35s0
# systemctl status hostapd-wlp65s0
# systemctl status hostapd-wlp70s0
#
# nix pkgs source
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ho/hostapd/package.nix
# https://w1.fi/hostapd/
# https://github.com/latelee/hostapd
#
# Giant NixPkgs PR: https://github.com/NixOS/nixpkgs/pull/222536

# [das@l2:~]$ lspci | grep -iE '(net|wi)'
# 01:00.0 Ethernet controller: Aquantia Corp. AQtion AQC107 NBase-T/IEEE 802.3an Ethernet Controller [Atlantic 10G] (rev 02)
# 02:00.0 PCI bridge: Advanced Micro Devices, Inc. [AMD] Matisse Switch Upstream
# 23:00.0 Network controller: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)
# 41:00.0 Network controller: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)
# 42:00.0 Network controller: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)
# 61:00.0 Network controller: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)

# [das@l2:~]$ ifconfig -a | grep Ether
# br0       Link encap:Ethernet  HWaddr 6A:9C:34:61:21:28
# docker0   Link encap:Ethernet  HWaddr 02:42:DE:0F:7E:B0
# enp1s0    Link encap:Ethernet  HWaddr E0:4F:43:E6:2D:B0
# wlp35s0   Link encap:Ethernet  HWaddr 28:A4:4A:27:E7:7D
# wlp65s0   Link encap:Ethernet  HWaddr 28:A4:4A:D7:86:74
# wlp66s0   Link encap:Ethernet  HWaddr 28:A4:4A:27:E7:73
# wlp97s0   Link encap:Ethernet  HWaddr 28:A4:4A:01:73:D6

# [das@l2:~/nixos/desktop/l2]$ iw dev | grep -A5 phy
# phy#15
#         Interface wlp35s0
#                 ifindex 27
#                 wdev 0xf00000001
#                 addr 28:a4:4a:27:e7:7d
#                 type managed
# --
# phy#14
#         Interface wlp66s0
#                 ifindex 26
#                 wdev 0xe00000001
#                 addr 28:a4:4a:27:e7:73
#                 type managed
# --
# phy#13
#         Interface wlp65s0
#                 ifindex 25
#                 wdev 0xd00000001
#                 addr 28:a4:4a:d7:86:74
#                 type managed
# --
# phy#12
#         Interface wlp97s0
#                 ifindex 24
#                 wdev 0xc00000001
#                 addr 28:a4:4a:01:73:d6
#                 type managed

# [das@l2:~/nixos/desktop/l2]$

# systemctl status hostapd.service
# journalctl -xeu hostapd.service

# remove
# sudo sh -c "rmmod iwlmvm || true && rmmod iwlwifi || true && rmmod mac80211 || true"
# add
# sudo sh -c "modprobe iwlmvm || true && modprobe iwlwifi || true && modprobe mac80211 || true"

# sudo strace -f -tt -s 256 -o hostapd_strace.log /nix/store/px5q7qqnrpw981i8ccg1cgx8p5pf4nc6-hostapd-2.11/bin/hostapd -dd /nix/store/1dbx6njz2acsw5hv5rw5x21pybr9nsb3-hostapd.conf

# cat /etc/systemd/system/hostapd.service

{ config, lib, pkgs, ... }:

let
  # List of Wi-Fi interfaces to manage
  wifiInterfaces = [ "wlp35s0" "wlp65s0" "wlp66s0" "wlp97s0" ];

  # Real MAC addresses for each interface (used for bssid=)
  ifaceMacs = {
    wlp35s0 = "28:A4:4A:27:E7:7D";
    wlp65s0 = "28:A4:4A:D7:86:74";
    wlp66s0 = "28:A4:4A:27:E7:73";
    wlp97s0 = "28:A4:4A:01:73:D6";
  };

  # Common SSID and WPA3 settings
  ssid = "myssid";
  psk = "supersecure";

  # Common AP parameters
  commonParams = iface: ''
    #
    ##### Configuration for ${iface} #####
    #
    ${if iface == builtins.elemAt wifiInterfaces 0 then "interface=${iface}" else "bss=${iface}"}
    bssid=${ifaceMacs.${iface}}
    ssid=${ssid}
    hw_mode=g
    channel=6
    ieee80211n=1
    ieee80211ac=1
    ieee80211ax=1
    wmm_enabled=1

    # WMM tuning
    wmm_ac_be_aifs=1
    wmm_ac_be_cwmin=4
    wmm_ac_be_cwmax=4
    wmm_ac_be_txop_limit=32
    wmm_ac_be_acm=0

    # WPA3-SAE settings
    wpa=2
    wpa_key_mgmt=SAE
    rsn_pairwise=CCMP
    sae_require_mfp=1
    ieee80211w=2
    ft_psk_generate_local=1
    mobility_domain=4f57
    ft_over_ds=1
    nas_identifier=${iface}-ap
    sae_password=${psk}
    bridge=br0
    macaddr_acl=0
  '';

  # Generate a single hostapd.conf for all BSSes
  hostapdConf = pkgs.writeText "hostapd.conf" (
    ''
      ctrl_interface=/run/hostapd
      country_code=US
      ieee80211d=1
      logger_syslog=-1
      logger_syslog_level=2
      logger_stdout=-1
      logger_stdout_level=2
    '' +
    lib.concatMapStringsSep "\n" commonParams wifiInterfaces
  );

in {
  systemd.services.hostapd = {
    description = "Unified hostapd service for multi-interface Wi-Fi";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];

    path = [ pkgs.hostapd pkgs.iproute2 pkgs.iw ];

    serviceConfig = {
      ExecStart = "${pkgs.hostapd}/bin/hostapd -dd ${hostapdConf}";
      Restart = "on-failure";

      Type = "simple";

      LimitNOFILE = 65535;

      MemoryMax = "1024M";
      CPUQuota = "100%";
    };
  };

  networking = {
    networkmanager.enable = false;
    useDHCP = false;

    # Define empty bridge device, do not enslave wifi interfaces directly
    bridges.br0.interfaces = [ ];

    interfaces."br0" = {
      ipv4.addresses = [{ address = "192.168.1.1"; prefixLength = 24; }];
      ipv6.addresses = [{ address = "fd00::1"; prefixLength = 64; }];
    };

    interfaces."enp1s0".useDHCP = true;

    nat.enable = true;
    nat.externalInterface = "enp1s0";
    nat.internalInterfaces = [ "br0" ];
  };
}

# modprobe nlmon
# sudo modprobe nlmon
# lsmod | grep nlmon
# sudo ip link add nlmon0 type nlmon
# sudo ip link set dev nlmon0 up
# sudo tcpdump -i nlmon0 -w netlink.pcap
# sudo chown das:das *.pcap

# https://jvns.ca/blog/2017/09/03/debugging-netlink-requests/

# end