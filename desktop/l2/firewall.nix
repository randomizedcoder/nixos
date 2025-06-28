{ config, pkgs, ... }:

{
  # Disable the default iptables firewall since we're using nftables
  networking.firewall.enable = false;

  # Enable nftables with connection tracking for maximum security
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet filter {
        chain input {
          type filter hook input priority 0; policy drop;

          # Enable connection tracking
          ct state established,related accept
          ct state invalid drop

          # Allow loopback
          iif lo accept
          oif lo accept

          # Allow SSH from anywhere
          tcp dport 22 accept

          # Allow DNS queries
          udp dport 53 accept
          tcp dport 53 accept

          # Allow DHCP
          udp dport 67 accept
          udp dport 547 accept

          # Allow ICMP (ping, etc.)
          icmp type echo-request accept
          icmpv6 type echo-request accept

          # Allow RA (Router Advertisement)
          icmpv6 type nd-router-advert accept
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          # Allow traffic from internal network to external
          # Use meta iifname to avoid interface existence check at load time
          meta iifname "br0" oifname "enp1s0" accept

          # Allow return traffic from external to internal
          meta iifname "enp1s0" oifname "br0" ct state established,related accept
        }

        chain output {
          type filter hook output priority 0; policy accept;
        }
      }

      table ip nat {
        chain prerouting {
          type nat hook prerouting priority dstnat;
        }

        chain postrouting {
          type nat hook postrouting priority srcnat;
          # IPv4 masquerading
          meta oifname "enp1s0" masquerade
        }
      }

      table ip6 nat {
        chain prerouting {
          type nat hook prerouting priority dstnat;
        }

        chain postrouting {
          type nat hook postrouting priority srcnat;
          # IPv6 masquerading
          meta oifname "enp1s0" masquerade
        }
      }
    '';
  };
}