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
#
#
# hostapd.nix

{ config, lib, pkgs, ... }:

let
  # List of Wi-Fi interfaces to manage
  wifiInterfaces = [ "wlp35s0" "wlp65s0" "wlp70s0" ];

  # Real MAC addresses for each interface (used for bssid=)
  ifaceMacs = {
    wlp35s0 = "28:A4:4A:27:E7:7D";
    wlp65s0 = "28:A4:4A:D7:86:74";
    wlp70s0 = "90:65:84:5E:6F:D2";
  };

  # Common SSID and WPA3 settings
  ssid = "myssid";
  psk = "supersecurepassword";

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

    preStart = ''
      for iface in ${builtins.concatStringsSep " " wifiInterfaces}; do
        ip link set dev "$iface" down || true
        iw dev "$iface" set type __ap || true
        ip link set dev "$iface" up
      done
      sleep 5
    '';

    path = [ pkgs.iproute2 pkgs.iw ];

    serviceConfig = {
      ExecStart = "${pkgs.hostapd}/bin/hostapd -d ${hostapdConf}";
      Restart = "on-failure";
      RuntimeDirectory = "hostapd";
      Type = "simple";
      LimitNOFILE = 65535;
      #CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
      #AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
      # ProtectSystem = "strict";
      # ProtectHome = true;
      # PrivateTmp = true;
      # NoNewPrivileges = true;
      # ReadWritePaths = [ "/run/hostapd" ];
      # DeviceAllow = [
      #   "/dev/wlp35s0"
      #   "/dev/wlp65s0"
      #   "/dev/wlp70s0"
      #   "/dev/rfkill"
      # ];
      # DevicePolicy = "auto";
      # DevicePolicy = "closed";
      # RestrictAddressFamilies = [
      #   "AF_UNIX"
      #   "AF_NETLINK"
      #   "AF_INET"
      #   "AF_INET6"
      # ];
      # ProtectKernelModules = true;
      # ProtectControlGroups = true;
      # ProtectKernelTunables = true;
      # ProtectClock = true;
      # LockPersonality = true;
      # RemoveIPC = true;
      # RestrictRealtime = true;
      # SystemCallArchitectures = "native";
      # RestrictNamespaces = true;

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

# end