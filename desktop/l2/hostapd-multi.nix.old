#
# l2/hostapd-multi.nix
#
# MediaTek MT7915e dual-band WiFi 6 card
# Uses udev rules to create stable interface names based on MAC addresses
#

{ config, lib, pkgs, ... }:

let
  # MediaTek MT7915e interfaces (stable names via udev rules below)
  # wlan_2g = MAC 00:0a:52:0d:d0:9a = 2.4GHz radio
  # wlan_5g = MAC 00:0a:52:0d:d0:9b = 5GHz radio
  radioIfaces = {
    wlan_2g = { band = "2g"; channel = 6; };    # 2.4GHz - channel 6 (non-overlapping)
    wlan_5g = { band = "5g"; channel = 36; };   # 5GHz - channel 36 (non-DFS)
  };

  commonSettings = {
    bridge = "br0";
    ieee80211w = 2;

    # WMM tuning (as recommended by Koen De Schepper, Nokia)
    wmm_ac_be_aifs = 1;
    wmm_ac_be_cwmin = 4;
    wmm_ac_be_cwmax = 4;
    wmm_ac_be_txop_limit = 32;
    wmm_ac_be_acm = 0;
  };

  commonAuth = {
    mode = "wpa3-sae";
    saePasswords = [{ password = "strongpassword"; }];
  };

  genRadio = iface: cfg: {
    countryCode = "US";
    band = cfg.band;
    channel = cfg.channel;
    # WiFi 6 (802.11ax) settings for MT7915e
    # settings = {
    #   ieee80211d = true;
    #   ieee80211h = false;
    #   he_su_beamformer = 1;
    #   he_su_beamformee = 1;
    # };

    networks.${iface} = {
      ssid = "myssid";
      authentication = commonAuth;
      settings = commonSettings;
    };
  };

in {

  # AX210 kernel bug
  # https://bugzilla.kernel.org/show_bug.cgi?id=206469#c2

  # Moved to configuration.nix
  #boot.initrd.preDeviceCommands = ''
  #  echo "Loading regulatory database early"
  #  cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db /lib/firmware/
  #  cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db.p7s /lib/firmware/
  #'';

  # This is now set in the configuration.nix
  # boot.extraModprobeConfig = ''
  #   options cfg80211 ieee80211_regdom=US
  #   options iwlwifi lar_disable=1
  # '';

  # install the firmware for the wireless interface
  # ls /lib/firmware/regulatory.db
  # see also: https://discourse.nixos.org/t/direct-firmware-load-for-regulatory-db-failed/16317
  hardware = {
    enableAllFirmware = true;
    enableRedistributableFirmware = true;
    wirelessRegulatoryDatabase = true;
    #firmware = with pkgs; [ wireless-regdb ];
  };

  # Stable interface names for MediaTek MT7915e based on MAC addresses
  # This ensures consistent naming across reboots
  services.udev.extraRules = ''
    # MediaTek MT7915e 2.4GHz radio
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:0a:52:0d:d0:9a", NAME="wlan_2g"
    # MediaTek MT7915e 5GHz radio
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:0a:52:0d:d0:9b", NAME="wlan_5g"
  '';

  systemd.tmpfiles.rules = [
    "L+ /lib/firmware/regulatory.db - - - - ${pkgs.wireless-regdb}/lib/firmware/regulatory.db"
    "L+ /lib/firmware/regulatory.db.p7s - - - - ${pkgs.wireless-regdb}/lib/firmware/regulatory.db.p7s"
    "d /run/radvd 0755 radvd radvd - -"
  ];

  systemd.services.set-regdom = {
    description = "Force regulatory domain before hostapd";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" "sysinit.target" ]; # Ensure network stack and devices are ready
    before = [ "hostapd.service" "network-online.target" ]; # Run before hostapd and general network comes up
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.iw}/bin/iw reg set US";
      ExecStopPost = "${pkgs.iw}/bin/iw reg get";
    };
  };

  # systemctl status hostapd
  services.hostapd.enable = true;
  services.hostapd.radios = lib.mapAttrs genRadio radioIfaces;

  # systemctl status kea-dhcp4-server.service
  services.kea = {
    dhcp4 = {
      enable = true;
      settings = {
        valid-lifetime = 3600;
        renew-timer = 900;
        rebind-timer = 1800;
        interfaces-config.interfaces = [ "br0" ];
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };
        subnet4 = [
          {
            id = 1;
            subnet = "192.168.1.0/24";
            pools = [{ pool = "192.168.1.100 - 192.168.1.200"; }];
            option-data = [
              { name = "routers"; data = "192.168.1.1"; }
              { name = "domain-name-servers"; data = "192.168.1.1"; }
            ];
          }
        ];
      };
    };
  };
  # services.prometheus.exporters.kea = {
  #   enable = true;
  #   openFirewall = true;
  #   #port = 9547; # default port ( https://mynixos.com/nixpkgs/option/services.prometheus.exporters.kea.port )
  #   targets = [ "/run/kea/kea-dhcp4.socket" ];
  # };

  # PowerDNS Recursor
  # sudo lsof -i :53
  # systemctl status pdns-recursor
  services.pdns-recursor = {
    enable = true;
    dns.address = [ "127.0.0.1" "::1" "192.168.1.1" "fd00::1" ];
    dns.allowFrom = [ "127.0.0.1/32" "::1/128" "192.168.1.0/24" "fd00::/64" ];
    yaml-settings = {
      recursor = {
        serve_rfc1918 = true;
      };
    };
  };

  # IPv6 SLAAC via radvd
  # systemctl status radvd
  services.radvd = {
    enable = true;
    config = ''
      interface br0 {
        AdvSendAdvert on;
        prefix fd00::/64 {
          AdvOnLink on;
          AdvAutonomous on;
        };
        RDNSS fd00::1 {
          AdvRDNSSLifetime 600;
        };
      };
    '';
  };

  # Add necessary capabilities to RADVD for ICMPv6 Router Advertisement
  systemd.services.radvd = {
    serviceConfig = {
      # Run as radvd user from the start
      User = "radvd";
      Group = "radvd";
      # Override ExecStart to remove -u radvd flag since we're already running as radvd user
      # Use -p flag to specify a writable PID file location
      ExecStart = lib.mkForce "${pkgs.radvd}/bin/radvd -n -p /run/radvd/radvd.pid -d 0 -C ${pkgs.writeText "radvd.conf" config.services.radvd.config}";
      # Let systemd manage the PID file
      PIDFile = "/run/radvd/radvd.pid";
      # Add CAP_NET_RAW capability to allow sending ICMPv6 messages
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_NET_BROADCAST" "CAP_NET_RAW" ];
      AmbientCapabilities = [ "CAP_NET_RAW" ];
      # Ensure the process can bind to privileged ports if needed
      NoNewPrivileges = false;
    };
  };

  # https://nixos.wiki/wiki/Systemd-networkd
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network.enable = true;

  #https://www.freedesktop.org/software/systemd/man/latest/systemd.netdev.html
  systemd.network.netdevs = {
    "br0" = {
      netdevConfig = {
        Kind = "bridge";
        Name = "br0";
      };
    };
  };

  # add dummy0 to force br0 up
  systemd.network.netdevs."dummy0" = {
    netdevConfig = {
      Kind = "dummy";
      Name = "dummy0";
    };
  };

  systemd.network.networks."dummy0" = {
    matchConfig.Name = "dummy0";
    networkConfig = {
      Bridge = "br0";
    };
  };

  # https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html
  systemd.network.networks = {
    "enp1s0" = {
      matchConfig.Name = "enp1s0";
      networkConfig = {
        DHCP = "ipv4";
        #IPv4Forwarding = true;
        #IPv6Forwarding = true;
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        # IPMasquerade handled by nftables for better control
        LLDP = true;
        EmitLLDP = true;
      };
      # # Explicitly enable Router Advertisement acceptance
      # ipv6AcceptRAConfig = {
      #   AcceptRA = true;
      #   UseDNS = false;  # We handle DNS ourselves
      #   UseDomains = false;
      # };
    };

    "br0" = {
      matchConfig.Name = "br0";
      networkConfig = {
        Address = [
          "192.168.1.1/24"
          "fd00::1/64"
        ];
        # IPv4Forwarding = true;
        # IPv6Forwarding = true;
        ConfigureWithoutCarrier = true;
      };
      linkConfig = {
        ActivationPolicy = "always-up";
      };
      # DualPI2 qdisc configured via systemd service (see below)
      # cakeConfig removed - was:
      # cakeConfig = {
      #   Bandwidth = "1000M";
      #   OverheadBytes = 8;
      #   CompensationMode = "ptm";
      #   NAT = true;
      #   FlowIsolationMode = "triple";
      #   PriorityQueueingPreset = "besteffort";
      # };
    };

    "wlan" = {
      matchConfig.Type = "wlan";
      linkConfig = {
        Unmanaged = true;
      };
    };

    # enp4s0f0np0 removed (interface no longer present)
  };

  # Disable conflicting resolvers and provide local one
  services.resolved.enable = false;
  networking.nameservers = [ "127.0.0.1" "::1" ];

  environment.etc."resolv.conf".text = ''
    # pdns
    nameserver 127.0.0.1
    nameserver ::1
    # emergency cloudflare
    nameserver 1.1.1.1
    nameserver 2606:4700:4700::1111
  '';

  # DualPI2 L4S AQM packet scheduler configuration
  # https://github.com/L4STeam/linux/wiki/DUALPI2
  # Available in kernel 6.17+ (merged September 2025)
  # Interfaces: enp1s0 (WAN), br0 (LAN bridge), wlan_2g (2.4GHz), wlan_5g (5GHz)
  systemd.services.dualpi2-qdisc = {
    description = "Configure DualPI2 qdisc on network interfaces";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "hostapd.service" ];
    wants = [ "hostapd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "dualpi2-setup" ''
        #!/bin/sh
        set -e

        TC="${pkgs.iproute2}/bin/tc"

        # Function to setup dualpi2 on an interface
        setup_dualpi2() {
          iface=$1
          # Remove existing qdisc (ignore errors if none exists)
          $TC qdisc del dev "$iface" root 2>/dev/null || true
          # Add dualpi2 qdisc
          # Parameters (using defaults):
          #   target: target delay (default 15ms)
          #   tupdate: PI controller update interval (default 16ms)
          #   alpha/beta: PI controller gains
          $TC qdisc add dev "$iface" root dualpi2
          echo "Configured dualpi2 on $iface"
        }

        # Wait a moment for interfaces to be ready
        sleep 2

        # Configure bridge (LAN) - main interface for WiFi clients
        if ip link show br0 > /dev/null 2>&1; then
          setup_dualpi2 br0
        fi

        # Configure WiFi interfaces
        if ip link show wlan_2g > /dev/null 2>&1; then
          setup_dualpi2 wlan_2g
        fi

        if ip link show wlan_5g > /dev/null 2>&1; then
          setup_dualpi2 wlan_5g
        fi

        # Log results
        echo "=== DualPI2 Configuration Results ===" > /tmp/dualpi2-qdisc.log
        echo "Timestamp: $(date)" >> /tmp/dualpi2-qdisc.log
        for iface in enp1s0 br0 wlan_2g wlan_5g; do
          echo "" >> /tmp/dualpi2-qdisc.log
          echo "=== $iface ===" >> /tmp/dualpi2-qdisc.log
          $TC qdisc show dev "$iface" >> /tmp/dualpi2-qdisc.log 2>&1 || echo "Interface not found" >> /tmp/dualpi2-qdisc.log
        done

        echo "DualPI2 qdisc configuration complete"
      '';
    };
  };
}

#systemctl status kea
#systemctl status pdns-recursor
#systemctl status radvd

# [das@l2:~/nixos/desktop/l2]$ sudo ethtool --driver enp1s0
# driver: atlantic
# version: 6.15.3
# firmware-version: 4.2.32
# expansion-rom-version:
# bus-info: 0000:01:00.0
# supports-statistics: yes
# supports-test: no
# supports-eeprom-access: no
# supports-register-dump: yes
# supports-priv-flags: yes

# [das@l2:~/nixos/desktop/l2]$ sudo ethtool --show-ring enp1s0
# Ring parameters for enp1s0:
# Pre-set maximums:
# RX:                     8184
# RX Mini:                n/a
# RX Jumbo:               n/a
# TX:                     8184
# TX push buff len:       n/a
# Current hardware settings:
# RX:                     2048
# RX Mini:                n/a
# RX Jumbo:               n/a
# TX:                     4096
# RX Buf Len:             n/a
# CQE Size:               n/a
# TX Push:                off
# RX Push:                off
# TX push buff len:       n/a
# TCP data split:         n/a

# [das@l2:~/nixos/desktop/l2]$ sudo ethtool --show-features enp1s0
# Features for enp1s0:
# rx-checksumming: on
# tx-checksumming: on
#         tx-checksum-ipv4: off [fixed]
#         tx-checksum-ip-generic: on
#         tx-checksum-ipv6: off [fixed]
#         tx-checksum-fcoe-crc: off [fixed]
#         tx-checksum-sctp: off [fixed]
# scatter-gather: on
#         tx-scatter-gather: on
#         tx-scatter-gather-fraglist: off [fixed]
# tcp-segmentation-offload: on
#         tx-tcp-segmentation: on
#         tx-tcp-ecn-segmentation: off [fixed]
#         tx-tcp-mangleid-segmentation: off
#         tx-tcp6-segmentation: on
#         tx-tcp-accecn-segmentation: off [fixed]
# generic-segmentation-offload: on
# generic-receive-offload: on
# large-receive-offload: off
# rx-vlan-offload: on
# tx-vlan-offload: on
# ntuple-filters: on
# receive-hashing: on
# highdma: off [fixed]
# rx-vlan-filter: on
# vlan-challenged: off [fixed]
# tx-gso-robust: off [fixed]
# tx-fcoe-segmentation: off [fixed]
# tx-gre-segmentation: off [fixed]
# tx-gre-csum-segmentation: off [fixed]
# tx-ipxip4-segmentation: off [fixed]
# tx-ipxip6-segmentation: off [fixed]
# tx-udp_tnl-segmentation: off [fixed]
# tx-udp_tnl-csum-segmentation: off [fixed]
# tx-gso-partial: on
# tx-tunnel-remcsum-segmentation: off [fixed]
# tx-sctp-segmentation: off [fixed]
# tx-esp-segmentation: off [fixed]
# tx-udp-segmentation: on
# tx-gso-list: off [fixed]
# tx-nocache-copy: off
# loopback: off [fixed]
# rx-fcs: off [fixed]
# rx-all: off [fixed]
# tx-vlan-stag-hw-insert: off [fixed]
# rx-vlan-stag-hw-parse: off [fixed]
# rx-vlan-stag-filter: off [fixed]
# l2-fwd-offload: off [fixed]
# hw-tc-offload: on
# esp-hw-offload: off [fixed]
# esp-tx-csum-hw-offload: off [fixed]
# rx-udp_tunnel-port-offload: off [fixed]
# tls-hw-tx-offload: off [fixed]
# tls-hw-rx-offload: off [fixed]
# rx-gro-hw: off [fixed]
# tls-hw-record: off [fixed]
# rx-gro-list: off
# macsec-hw-offload: off [fixed]
# rx-udp-gro-forwarding: off
# hsr-tag-ins-offload: off [fixed]
# hsr-tag-rm-offload: off [fixed]
# hsr-fwd-offload: off [fixed]
# hsr-dup-offload: off [fixed]

# [das@l2:~/nixos/desktop/l2]$

# [das@l2:~/nixos/desktop/l2]$ sudo ethtool --show-coalesce enp1s0
# Coalesce parameters for enp1s0:
# Adaptive RX: n/a  TX: n/a
# stats-block-usecs:      n/a
# sample-interval:        n/a
# pkt-rate-low:           n/a
# pkt-rate-high:          n/a

# rx-usecs:       256
# rx-frames:      0
# rx-usecs-irq:   n/a
# rx-frames-irq:  n/a

# tx-usecs:       1022
# tx-frames:      0
# tx-usecs-irq:   n/a
# tx-frames-irq:  n/a

# rx-usecs-low:   n/a
# rx-frame-low:   n/a
# tx-usecs-low:   n/a
# tx-frame-low:   n/a

# rx-usecs-high:  n/a
# rx-frame-high:  n/a
# tx-usecs-high:  n/a
# tx-frame-high:  n/a

# CQE mode RX: n/a  TX: n/a

# tx-aggr-max-bytes:      n/a
# tx-aggr-max-frames:     n/a
# tx-aggr-time-usecs:     n/a


# [das@l2:~/nixos/desktop/l2]$

# end