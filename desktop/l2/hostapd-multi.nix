#
# hostapd-multi.nix
#

{ config, lib, pkgs, ... }:

let
  radioIfaces = {
    # non-DFS channels
    wlp35s0 = 36;
    wlp65s0 = 40;
    wlp66s0 = 44;
    wlp97s0 = 48;
  };

  commonSettings = {
    bridge = "br0";
    ieee80211w = 2;

    # WMM tuning
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

  genRadio = iface: channel: {
    countryCode = "US";
    band = "5g";
    channel = channel;

    networks.${iface} = {
      ssid = "myssid";
      authentication = commonAuth;
      settings = commonSettings;
    };
  };

in {
  # systemctl status kea
  services.hostapd.enable = true;
  services.hostapd.radios = lib.genAttrs (builtins.attrNames radioIfaces)
    (iface: genRadio iface radioIfaces.${iface});

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

  # services.dnsmasq = {
  #   enable = true;
  #   resolveLocalQueries = false;

  #   settings = {
  #     port = 0; # disable dns
  #     interface = "br0";
  #     bind-interfaces = true;

  #     dhcp-range = "192.168.1.100,192.168.1.199,12h";
  #     dhcp-option = [
  #       "option:router,192.168.1.1"
  #       "option:dns-server,192.168.1.1"
  #     ];
  #   };
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

  # # IPv6 SLAAC via radvd
  # # systemctl status radvd
  # services.radvd = {
  #   enable = true;
  #   config = ''
  #     interface br0 {
  #       AdvSendAdvert on;
  #       prefix fd00::/64 {
  #         AdvOnLink on;
  #         AdvAutonomous on;
  #       };
  #       RDNSS fd00::1 {
  #         AdvRDNSSLifetime 600;
  #       };
  #     };
  #   '';
  # };

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
        IPv6AcceptRA = true;
        IPv6PrivacyExtensions = true;
        #IPMasquerade = true;
        LLDP = true;
        EmitLLDP = true;
      };
    };

    "br0" = {
      matchConfig.Name = "br0";
      networkConfig = {
        Address = [
          "192.168.1.1/24"
          "fd00::1/64"
        ];
        ConfigureWithoutCarrier = true;
      };
      linkConfig = {
        ActivationPolicy = "always-up";
      };
      cakeConfig = {
        Bandwidth = "100M";  # Set your desired bandwidth
        OverheadBytes = 8;
        CompensationMode = "ptm";  # e.g. for DSL, change as needed
        NAT = true;
        FlowIsolationMode = "triple";
        PriorityQueueingPreset = "besteffort";
      };
    };

    "wlan" = {
      matchConfig.Type = "wlan";
      linkConfig = {
        Unmanaged = true;
      };
    };
  };

  # # Networking setup
  # networking = {

  #   networkmanager.enable = false;

  #   # useNetworkd = true;

  #   # useDHCP = false;

  #   # # Need an interface to bring it up, to allow the IP assignment
  #   # bridges.br0.interfaces = [ ];

  #   # interfaces.br0 = {
  #   #   ipv4.addresses = [{
  #   #     address = "192.168.1.1";
  #   #     prefixLength = 24;
  #   #   }];
  #   #   ipv6.addresses = [{
  #   #     address = "fd00::1";
  #   #     prefixLength = 64;
  #   #   }];
  #   # };

  #   # interfaces.enp1s0.useDHCP = true;

  #   nat = {
  #     enable = true;
  #     externalInterface = "enp1s0";
  #     internalInterfaces = [ "br0" ];
  #   };
  # };

  # Disable conflicting resolvers and provide local one
  services.resolved.enable = false;
  networking.nameservers = [ "127.0.0.1" "::1" ];

  environment.etc."resolv.conf".text = ''
    # dnsmasq
    nameserver 127.0.0.1
    nameserver ::1
    # emergency cloudflare
    nameserver 1.1.1.1
    nameserver 2606:4700:4700::1111
  '';
}

#systemctl status kea
#systemctl status pdns-recursor
#systemctl status radvd

# end