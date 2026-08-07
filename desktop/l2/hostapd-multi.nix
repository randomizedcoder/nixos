#
# l2/hostapd-multi.nix
#
# 4× MediaTek MT7925 WiFi 7 (802.11be) cards as access points.
#
# Purpose: keep the radios active (not power-saving) so TSF counters
# are always running, enabling tsf-sync PTP to read live timestamps.
#
# Each card is tri-band (2.4/5/6GHz). We spread across non-overlapping
# channels to minimize co-channel interference:
#   wls1 (25:00.0) → 5GHz ch36   (UNII-1, indoor)
#   wls2 (26:00.0) → 5GHz ch36   (co-channel with wls1 for tsf_set
#                                  cross-card beacon observation test;
#                                  previously ch149)
#   wls3 (27:00.0) → 2.4GHz ch1
#   wls4 (28:00.0) → 2.4GHz ch6
#
# No bridge, no DHCP, no NAT — just hostapd APs for TSF sync testing.
# Clients can associate but won't get IP addresses unless you add a
# DHCP server or bridge to an upstream interface.
#
{ config, lib, pkgs, ... }:

let
  # Stable interface names assigned by the kernel (wlsN).
  # If these change across reboots, add udev rules to pin by MAC.
  #
  # wls1: 0c:cd:b4:38:73:01  PCI 25:00.0  phy0
  # wls2: 0c:cd:b4:38:74:e3  PCI 26:00.0  phy1
  # wls3: 0c:cd:b4:38:7d:c9  PCI 27:00.0  phy2
  # wls4: 0c:cd:b4:38:74:e1  PCI 28:00.0  phy3

  commonAuth = {
    mode = "wpa3-sae";
    saePasswords = [{ password = "tsf-sync-lab"; }];
  };

  commonSettings = {
    ieee80211w = 2;    # MFP required (mandatory for WPA3)
  };

in {

  hardware = {
    enableAllFirmware = true;
    enableRedistributableFirmware = true;
    wirelessRegulatoryDatabase = true;
  };

  # Force US regulatory domain before hostapd starts
  systemd.services.set-regdom = {
    description = "Force regulatory domain before hostapd";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" "sysinit.target" ];
    before = [ "hostapd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.iw}/bin/iw reg set US";
    };
  };

  services.hostapd = {
    enable = true;
    radios = {
      # ── wls1: 5 GHz channel 36 ──
      wls1 = {
        countryCode = "US";
        band = "5g";
        channel = 36;
        networks.wls1 = {
          ssid = "tsf-lab-5g-1";
          authentication = commonAuth;
          settings = commonSettings;
        };
      };

      # ── wls2: 5 GHz channel 36 (co-channel with wls1 for tsf_set test) ──
      wls2 = {
        countryCode = "US";
        band = "5g";
        channel = 36;
        networks.wls2 = {
          ssid = "tsf-lab-5g-2";
          authentication = commonAuth;
          settings = commonSettings;
        };
      };

      # ── wls3: 2.4 GHz channel 1 ──
      wls3 = {
        countryCode = "US";
        band = "2g";
        channel = 1;
        networks.wls3 = {
          ssid = "tsf-lab-2g-1";
          authentication = commonAuth;
          settings = commonSettings;
        };
      };

      # ── wls4: 2.4 GHz channel 6 ──
      wls4 = {
        countryCode = "US";
        band = "2g";
        channel = 6;
        networks.wls4 = {
          ssid = "tsf-lab-2g-2";
          authentication = commonAuth;
          settings = commonSettings;
        };
      };
    };
  };

  # Mark WiFi interfaces as unmanaged by scripted networking
  # so hostapd has full control.
  networking.interfaces.wls1.useDHCP = false;
  networking.interfaces.wls2.useDHCP = false;
  networking.interfaces.wls3.useDHCP = false;
  networking.interfaces.wls4.useDHCP = false;
}
