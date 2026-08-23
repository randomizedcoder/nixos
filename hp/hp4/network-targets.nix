#
# nixos/hp/hp4/network-targets.nix
#
# SINGLE SOURCE OF TRUTH for the ICMP-pingable monitoring targets shared by both
# smokeping.nix (web UI + RRD) and blackbox.nix/prometheus.nix (Prometheus metrics
# + Grafana + alerting). Previously each of those files kept its OWN copy of the
# device list, and they drifted — smokeping got the full IPv4+IPv6 + access-point
# treatment while blackbox was left probing only a few external hosts. Define a
# device here ONCE and both monitoring paths pick it up.
#
# Only the ICMP categories live here (DNS servers, internet hosts, network devices,
# access points) — the HTTP and DNS-lookup probes stay in each tool because their
# probe syntax differs (smokeping Curl/DNS vs blackbox http/dns modules).
#
# Usage:  nt = import ./network-targets.nix { inherit lib; };
#         nt.categories   # attrset of { title; menu; targets = { key = {name; host;}; }; }
#         nt.icmpV4        # flat list of { host; name; category; key; } for v4 literals
#         nt.icmpV6        # ditto for v6 literals
#         nt.byFamilyAndCategory "ip4"  # [{ category; hosts=[...]; }] grouped, v4 only

{ lib }:

let
  # IPv6 GUA prefix delegated by Charter to the management VLAN
  # (2603:8002:ea00:6800::/64). Devices SLAAC EUI-64 addresses in it (host bits from
  # MAC), except the UXG which uses ::1 and the switches which got STATIC mgmt v6
  # matching their v4 last octet. NOTE: ISP-delegated — if Charter re-delegates a new
  # prefix, update THIS one line and every v6 target below follows.
  v6pfx = "2603:8002:ea00:6800";

  isIPv6 = host: lib.hasInfix ":" host;

  categories = {
    # DNS servers — ICMP reachability
    "DNSServers" = {
      title = "DNS Server Connectivity (ICMP Ping)";
      menu = "DNS Servers";
      targets = {
        "Google_DNS_IPv4"           = { name = "Google DNS IPv4";            host = "8.8.8.8"; };
        "Google_DNS_IPv6"           = { name = "Google DNS IPv6";            host = "2001:4860:4860::8888"; };
        "Cloudflare_DNS_IPv4"       = { name = "Cloudflare DNS IPv4";        host = "1.1.1.1"; };
        "Cloudflare_DNS_IPv6"       = { name = "Cloudflare DNS IPv6";        host = "2606:4700:4700::1111"; };
        "Cloudflare_DNS_Secondary_IPv4" = { name = "Cloudflare DNS Secondary IPv4"; host = "1.0.0.1"; };
        "Cloudflare_DNS_Secondary_IPv6" = { name = "Cloudflare DNS Secondary IPv6"; host = "2606:4700:4700::1001"; };
      };
    };

    # Internet reachability (external anchors)
    "Internet" = {
      title = "Internet Connectivity Monitoring";
      menu = "Internet Connectivity";
      targets = {
        "Google_IPv4"          = { name = "Google.com IPv4"; host = "142.250.190.78"; };
        "Google_IPv6"          = { name = "Google.com IPv6"; host = "2607:f8b0:4007:811::200e"; };
        "Facebook_IPv6"        = { name = "Facebook IPv6";   host = "2a03:2880:f10d:183:face:b00c:0:25de"; };
        "Yahoo_IPv6"           = { name = "Yahoo IPv6";      host = "2001:4998:24:120d::1:0"; };
        "crowncastle-ic-386848" = { name = "crowncastle-ic-386848"; host = "62.115.8.253"; };
        "SidenLAX1"            = { name = "SidenLAX1";          host = "160.72.7.68"; };
        "SidenLAX1_Internal"   = { name = "SidenLAX1_Internal"; host = "160.72.7.65"; };
        "SidenLAX_dcops0_93"   = { name = "SidenLAX_dcops0_93"; host = "160.72.7.93"; };
        "SidenLAX_dcops1_94"   = { name = "SidenLAX_dcops1_94"; host = "160.72.7.94"; };
      };
    };

    # Local network devices and gateways (IPv4 + IPv6)
    "NetworkDevices" = {
      title = "Network Devices and Gateways";
      menu = "Network Devices";
      targets = {
        "SpectrumLAG60_4"   = { name = "SpectrumLAG60_4"; host = "76.167.31.29"; };
        "SpectrumLAG60_6"   = { name = "SpectrumLAG60_6"; host = "2605:e000:0:4::8:1d5"; };
        "SpectrumGateway4"  = { name = "SpectrumGateway4"; host = "172.88.16.1"; };
        "SpectrumGateway6"  = { name = "SpectrumGateway6"; host = "2605:e000:2fc0:f::1"; };
        "RouterUSGdefault"    = { name = "Gateway Pro / USG (IPv4)"; host = "172.16.50.1"; };
        # The UXG uses ::1 on the LAN (not an EUI-64 SLAAC addr); verified reachable.
        "RouterUSGdefault_v6" = { name = "Gateway Pro / USG (IPv6)"; host = "${v6pfx}::1"; };
        "Juniper2300"         = { name = "Juniper EX2300 core (IPv4)"; host = "172.16.50.12"; };
        "Juniper2300_v6"      = { name = "Juniper EX2300 core (IPv6)"; host = "${v6pfx}::12"; };
        "Juniper2200_office"    = { name = "Juniper EX2200 office (IPv4)"; host = "172.16.50.11"; };
        "Juniper2200_office_v6" = { name = "Juniper EX2200 office (IPv6)"; host = "${v6pfx}::11"; };
        "CRS310"    = { name = "CRS310 MikroTik (IPv4)"; host = "172.16.50.17"; };
        "CRS310_v6" = { name = "CRS310 MikroTik (IPv6)"; host = "${v6pfx}::17"; };
        "CloudKey"  = { name = "Cloud Key Controller"; host = "172.16.50.5"; };
        "USW_8_PoE_150W"    = { name = "US-8-150W Switch (IPv4)"; host = "172.16.50.201"; };
        "USW_8_PoE_150W_v6" = { name = "US-8-150W Switch (IPv6)"; host = "${v6pfx}:b6fb:e4ff:fecf:f7c9"; };
        "USW_Flex_2_5G" = { name = "USW Flex 2.5G Switch"; host = "172.16.50.151"; };
        # USW_Flex_2_5G_v6: has v6 but not on its EUI-64 addr (privacy?) — needs its real address.
        "Netgear_GS108PEv3" = { name = "Netgear GS108PEv3"; host = "172.16.50.119"; };
      };
    };

    # UniFi access points — SLAAC EUI-64 globals (host bits from each MAC), verified
    # reachable via fping. AC Pro Cabinet Downstairs (172.16.50.135) removed 2026-08-23.
    "AccessPoints" = {
      title = "UniFi Access Points (ICMP Ping, IPv4 + IPv6)";
      menu = "Access Points";
      targets = {
        "AP_U7Pro_Dave"        = { name = "U7 Pro Dave's Office (IPv4)"; host = "172.16.50.237"; };
        "AP_U7Pro_Dave_v6"     = { name = "U7 Pro Dave's Office (IPv6)"; host = "${v6pfx}:9e05:d6ff:feb0:3466"; };
        "AP_U7Pro_Downstairs"    = { name = "U7 Pro Downstairs (IPv4)"; host = "172.16.50.67"; };
        "AP_U7Pro_Downstairs_v6" = { name = "U7 Pro Downstairs (IPv6)"; host = "${v6pfx}:9e05:d6ff:feaf:1795"; };
        "AP_U6Plus"    = { name = "U6+ (IPv4)"; host = "172.16.50.53"; };
        "AP_U6Plus_v6" = { name = "U6+ (IPv6)"; host = "${v6pfx}:f6e2:c6ff:fe43:2c88"; };
        "AP_ACPro_Naomi"    = { name = "AC Pro Naomi (IPv4)"; host = "172.16.50.107"; };
        "AP_ACPro_Naomi_v6" = { name = "AC Pro Naomi (IPv6)"; host = "${v6pfx}:f29f:c2ff:fe70:e645"; };
        "AP_ACPro_WestBed"    = { name = "AC Pro West Bed (IPv4)"; host = "172.16.50.189"; };
        "AP_ACPro_WestBed_v6" = { name = "AC Pro West Bed (IPv6)"; host = "${v6pfx}:feec:daff:fe80:4c55"; };
        "AP_ACLR_Balcony"    = { name = "AC LR Balcony (IPv4)"; host = "172.16.50.163"; };
        "AP_ACLR_Balcony_v6" = { name = "AC LR Balcony (IPv6)"; host = "${v6pfx}:76ac:b9ff:fe2c:c53a"; };
        "AP_ACPro_EastBed"    = { name = "AC Pro East Bed (IPv4)"; host = "172.16.50.113"; };
        "AP_ACPro_EastBed_v6" = { name = "AC Pro East Bed (IPv6)"; host = "${v6pfx}:e263:daff:fea6:54d3"; };
        "AP_ACPro_Rack"    = { name = "AC Pro Rack (IPv4)"; host = "172.16.50.148"; };
        "AP_ACPro_Rack_v6" = { name = "AC Pro Rack (IPv6)"; host = "${v6pfx}:feec:daff:fef3:22b0"; };
        "AP_ACPro_Downstairs"    = { name = "AC Pro Downstairs (IPv4)"; host = "172.16.50.238"; };
        "AP_ACPro_Downstairs_v6" = { name = "AC Pro Downstairs (IPv6)"; host = "${v6pfx}:f29f:c2ff:fea9:56ca"; };
      };
    };
  };

  # Flat list of every ICMP target, tagged with its category + key.
  icmpFlat = lib.flatten (lib.mapAttrsToList (categoryName: category:
    lib.mapAttrsToList (targetName: target: {
      inherit (target) host name;
      category = categoryName;
      key = "${categoryName}_${targetName}";
    }) category.targets
  ) categories);

  icmpV4 = lib.filter (e: !isIPv6 e.host) icmpFlat;
  icmpV6 = lib.filter (e: isIPv6 e.host) icmpFlat;

  # Group one family's hosts by category → [{ category; hosts = [ ... ]; }]
  # (used to build Prometheus static_configs that keep a per-category label).
  byFamilyAndCategory = family:
    let
      entries = if family == "ip6" then icmpV6 else icmpV4;
      cats = lib.unique (map (e: e.category) entries);
    in map (cat: {
      category = cat;
      hosts = map (e: e.host) (lib.filter (e: e.category == cat) entries);
    }) cats;

in {
  inherit v6pfx isIPv6 categories icmpFlat icmpV4 icmpV6 byFamilyAndCategory;
}
