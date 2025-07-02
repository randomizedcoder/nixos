#
# l2/firewall.nix
#
# Firewall configuration for WiFi access point
#
# # List all rules (most common)
# sudo nft list ruleset

# # List specific table
# sudo nft list table inet filter

# # List specific chain
# sudo nft list chain inet filter input

# # Show rules with handles (useful for deleting specific rules)
# sudo nft list ruleset -a

# # Monitor nftables events in real-time
# sudo nft monitor

# # Monitor specific events (new rules, deleted rules, etc.)
# sudo nft monitor new rules
# sudo nft monitor destroy rules

# # Show packet counters
# sudo nft list ruleset -n

# # Show rules with statistics
# sudo nft list ruleset -s
# #
# # See all filter rules (input, forward, output chains)
# sudo nft list table inet filter

# # See NAT rules
# sudo nft list table ip nat
# sudo nft list table ip6 nat
#

{ config, pkgs, ... }:

let
  # Interface configuration - customize these for your machine
  wanInterface = "enp1s0";      # External/WAN interface
  lanInterface = "br0";         # Internal/LAN bridge interface
  upstreamLanPrefix = "172.16.0.0/16";  # Upstream LAN prefix for management access
  internalIPv4Prefix = "192.168.1.0/24"; # Internal IPv4 subnet
  internalIPv6Prefix = "fd00::/64";      # Internal IPv6 subnet

in {
  # Disable the default iptables firewall since we're using nftables
  networking.firewall.enable = false;

  # Enable nftables with connection tracking for maximum security
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet filter {
        # Define sets for special-purpose address ranges (RFC 6890)
        # These improve performance and readability
        set special_purpose_ipv4 {
          type ipv4_addr
          flags interval
          elements = {
            0.0.0.0/8,           # "This" Network
            10.0.0.0/8,          # Private-Use
            100.64.0.0/10,       # Shared Address Space
            169.254.0.0/16,      # Link Local
            192.0.0.0/24,        # IETF Protocol Assignments
            192.0.2.0/24,        # TEST-NET-1
            192.88.99.0/24,      # IPv6 to IPv4 Relay
            # 192.168.0.0/16,    # Private-Use (EXCLUDED - allocated to 192.168.1.0/24)
            198.18.0.0/15,       # Device Benchmark
            198.51.100.0/24,     # TEST-NET-2
            203.0.113.0/24,      # TEST-NET-3
            224.0.0.0/3          # Multicast
          }
        }

        set special_purpose_ipv6 {
          type ipv6_addr
          flags interval
          elements = {
            ::/128,              # Unspecified Address
            ::ffff:0:0/96,       # IPv4-mapped Address
            64:ff9b::/96,        # IPv4-IPv6 Translation
            100::/64,            # Discard-Only Address Block
            2001::/32,           # TEREDO
            2001:2::/48,         # Benchmarking
            2001:db8::/32,       # Documentation
            2002::/16,           # 6to4
            fc00::/7,            # Unique Local
            fe80::/10,           # Link-Local
            ff00::/8             # Multicast
          }
        }

        # Define sets for loopback addresses
        set loopback_ipv4 {
          type ipv4_addr
          flags interval
          elements = {
            127.0.0.0/8          # IPv4 Loopback
          }
        }

        set loopback_ipv6 {
          type ipv6_addr
          flags interval
          elements = {
            ::1/128              # IPv6 Loopback
          }
        }

        # Define sets for common service ports
        set ssh_ports {
          type inet_service
          elements = {
            22                   # SSH
          }
        }

        set dns_ports {
          type inet_service
          elements = {
            53                   # DNS (TCP and UDP)
          }
        }

        set dhcp_ports {
          type inet_service
          elements = {
            67,                  # DHCPv4 Server
            547                  # DHCPv6 Server
          }
        }

        # Define sets for ICMP types
        set icmp_allowed {
          type icmp_type
          elements = {
            echo-request,        # Ping request
            echo-reply,          # Ping reply
            destination-unreachable,  # Host/network unreachable
            time-exceeded,            # TTL exceeded
            parameter-problem         # Parameter problem
          }
        }

        # Define sets for ICMPv6 types
        set icmpv6_allowed {
          type icmpv6_type
          elements = {
            echo-request,        # Ping request
            echo-reply,          # Ping reply
            destination-unreachable,  # Host/network unreachable
            time-exceeded,            # TTL exceeded
            parameter-problem,        # Parameter problem
            packet-too-big,           # Path MTU Discovery
            nd-router-solicit,        # Router solicitation
            nd-router-advert,         # Router advertisement
            nd-neighbor-solicit,      # Neighbor solicitation
            nd-neighbor-advert        # Neighbor advertisement
          }
        }

        # CrowdSec blacklist set for dynamic threat blocking
        set blacklist {
          type ipv4_addr
          flags timeout
        }

        # CrowdSec IPv6 blacklist set
        set blacklist6 {
          type ipv6_addr
          flags timeout
        }

        chain input {
          type filter hook input priority 0; policy drop;

          # Early drop for invalid packets
          ct state invalid drop

          # Drop fragmented packets (potential evasion technique)
          ip frag-off & 0x1fff != 0 drop

          # Drop packets with invalid TCP flag combinations
          tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn|rst|psh|ack|urg) drop
          tcp flags & (fin|syn) == (fin|syn) drop
          tcp flags & (syn|rst) == (syn|rst) drop

          # Drop traffic from blacklisted IPs (CrowdSec integration)
          ip saddr @blacklist drop
          ip6 saddr @blacklist6 drop

          # Allow established and related connections
          ct state established,related accept

          # Accept all traffic on the loopback interface, and drop spoofed
          # loopback packets on any other interface.
          iif lo accept
          iif != "lo" ip saddr @loopback_ipv4 drop
          iif != "lo" ip daddr @loopback_ipv4 drop
          iif != "lo" ip6 saddr @loopback_ipv6 drop
          iif != "lo" ip6 daddr @loopback_ipv6 drop

          # Drop incoming traffic from special-purpose/unroutable source addresses (RFC 6890)
          # This provides strong anti-spoofing protection for the router itself.
          ip saddr @special_purpose_ipv4 drop
          ip6 saddr @special_purpose_ipv6 drop

          # Allow management and network services from the internal interface (${lanInterface})
          # Rate limit SSH to prevent brute force attacks
          iifname "${lanInterface}" tcp dport @ssh_ports ct state new limit rate 6/minute accept
          iifname "${lanInterface}" tcp dport @ssh_ports ct state established,related accept

          # DNS and DHCP services
          iifname "${lanInterface}" udp dport @dns_ports accept
          iifname "${lanInterface}" tcp dport @dns_ports accept
          iifname "${lanInterface}" udp dport @dhcp_ports accept

          # Allow all traffic from the trusted upstream LAN (${upstreamLanPrefix}) on the WAN port.
          # This allows management of the router from the upstream LAN.
          iifname "${wanInterface}" ip saddr ${upstreamLanPrefix} accept
          # TODO: Add a similar rule to allow traffic from the upstream IPv6 LAN once its prefix is known.

          # Allow essential ICMP/ICMPv6 traffic on internal and external interfaces
          # Rate limit ICMP echo requests to prevent ping floods
          iifname "${lanInterface}" icmp type echo-request limit rate 10/second accept
          iifname "${lanInterface}" icmp type @icmp_allowed accept
          iifname "${lanInterface}" icmpv6 type echo-request limit rate 10/second accept
          iifname "${lanInterface}" icmpv6 type @icmpv6_allowed accept

          # External interface ICMP/ICMPv6 (rate limited)
          iifname "${wanInterface}" icmp type echo-request limit rate 5/second accept
          iifname "${wanInterface}" icmp type @icmp_allowed accept
          iifname "${wanInterface}" icmpv6 type echo-request limit rate 5/second accept
          iifname "${wanInterface}" icmpv6 type @icmpv6_allowed accept

          # Log and drop everything else
          log prefix "[nft-input-drop] " limit rate 5/minute drop
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          # Early drop for invalid packets being forwarded
          ct state invalid drop

          # Drop fragmented packets being forwarded
          ip frag-off & 0x1fff != 0 drop

          # Drop packets with invalid TCP flag combinations
          tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn|rst|psh|ack|urg) drop
          tcp flags & (fin|syn) == (fin|syn) drop
          tcp flags & (syn|rst) == (syn|rst) drop

          # Add explicit anti-spoofing drops for known-bad traffic.
          # Drop any spoofed loopback traffic trying to be forwarded.
          ip saddr @loopback_ipv4 drop
          ip daddr @loopback_ipv4 drop
          ip6 saddr @loopback_ipv6 drop
          ip6 daddr @loopback_ipv6 drop

          # Drop traffic from internal clients pretending to be on the upstream LAN.
          iifname "${lanInterface}" ip saddr ${upstreamLanPrefix} drop

          # Drop traffic from internal clients to private/reserved ranges.
          # This prevents traffic from being forwarded to non-routable destinations.
          # Based on IANA Special-Purpose Address Registry (RFC 6890)
          iifname "${lanInterface}" oifname "${wanInterface}" ip daddr @special_purpose_ipv4 drop
          iifname "${lanInterface}" oifname "${wanInterface}" ip6 daddr @special_purpose_ipv6 drop

          # Allow return traffic from external to internal (most common case, check first)
          iifname "${wanInterface}" oifname "${lanInterface}" ct state established,related accept

          # Rate limit new connections to prevent resource exhaustion
          ct state new limit rate 500/second accept

          # Allow traffic from internal clients (known subnets) to external network
          iifname "${lanInterface}" oifname "${wanInterface}" ip saddr ${internalIPv4Prefix} accept
          iifname "${lanInterface}" oifname "${wanInterface}" ip6 saddr ${internalIPv6Prefix} accept

          # Allow essential ICMP/ICMPv6 forwarding for proper network operation
          # ICMP for Path MTU Discovery and error reporting
          iifname "${wanInterface}" oifname "${lanInterface}" icmp type @icmp_allowed accept
          iifname "${lanInterface}" oifname "${wanInterface}" icmp type @icmp_allowed accept

          # ICMPv6 for IPv6 operation (including Path MTU Discovery)
          iifname "${wanInterface}" oifname "${lanInterface}" icmpv6 type @icmpv6_allowed accept
          iifname "${lanInterface}" oifname "${wanInterface}" icmpv6 type @icmpv6_allowed accept

          # Log and drop everything else
          log prefix "[nft-forward-drop] " limit rate 5/minute drop
        }

        chain output {
          type filter hook output priority 0; policy accept;

          # Drop invalid packets originating from the local machine
          ct state invalid drop

          # Drop fragmented packets from router
          ip frag-off & 0x1fff != 0 drop

          # Drop packets with invalid TCP flag combinations
          tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn|rst|psh|ack|urg) drop
          tcp flags & (fin|syn) == (fin|syn) drop
          tcp flags & (syn|rst) == (syn|rst) drop

          # Drop spoofed loopback packets on non-loopback interfaces.
          # Legitimate traffic to/from loopback addresses should only be on the 'lo' interface.
          oif != "lo" ip saddr @loopback_ipv4 drop
          oif != "lo" ip daddr @loopback_ipv4 drop
          oif != "lo" ip6 saddr @loopback_ipv6 drop
          oif != "lo" ip6 daddr @loopback_ipv6 drop

          # Allow essential ICMPv6 traffic from router (Router Advertisement, Neighbor Advertisement, etc.)
          oifname "${lanInterface}" icmpv6 type @icmpv6_allowed accept
          oifname "${wanInterface}" icmpv6 type @icmpv6_allowed accept

          # Block sending traffic to private/reserved ranges (regardless of interface)
          # with exceptions for allocated subnets to prevent IP leakage and network access
          # Based on IANA Special-Purpose Address Registry (RFC 6890)
          # Exclude our allocated subnets from the blocking
          ip daddr != ${internalIPv4Prefix} ip daddr @special_purpose_ipv4 drop
          ip6 daddr != ${internalIPv6Prefix} ip6 daddr @special_purpose_ipv6 drop

          # Block allocated subnets from going out the WAN interface (${wanInterface})
          # to prevent internal network leakage
          oifname "${wanInterface}" ip daddr ${internalIPv4Prefix} drop
          oifname "${wanInterface}" ip6 daddr ${internalIPv6Prefix} drop

          # Allow allocated subnets to go out the internal interface (${lanInterface})
          # for legitimate internal network communication
          oifname "${lanInterface}" ip daddr ${internalIPv4Prefix} accept
          oifname "${lanInterface}" ip6 daddr ${internalIPv6Prefix} accept
        }
      }

      table ip nat {
        chain prerouting {
          type nat hook prerouting priority dstnat;
        }

        chain postrouting {
          type nat hook postrouting priority srcnat;
          # IPv4 masquerading
          oifname "${wanInterface}" masquerade
        }
      }

      table ip6 nat {
        chain prerouting {
          type nat hook prerouting priority dstnat;
        }

        chain postrouting {
          type nat hook postrouting priority srcnat;
          # IPv6 masquerading
          oifname "${wanInterface}" masquerade
        }
      }
    '';
  };
}