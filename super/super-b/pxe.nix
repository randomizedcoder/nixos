#
# ~/nixos/super/super-b/pxe.nix — anycast PXE/netboot server for the super nodes.
#
# Every node that imports this runs the SAME service, bound to the internal
# anycast VIP 10.241.10.20 (already on dummy1 + advertised by bird in routing.nix).
# The ToRs relay PXE clients' DHCP (VLAN 402) to 10.241.10.20; BGP-ECMP delivers it
# to any live node → N-way redundant provisioning. See the design at
# ../../Downloads/nfb-ladc-asa01/... (super-d-deployment doc + the plan).
#
# Boot chain (HTTP-first — the initrd is large): NIC ROM --TFTP(~1MB ipxe)-->
# ipxe --HTTP--> netboot.ipxe --HTTP--> bzImage + initrd. atftpd carries ONLY the
# tiny iPXE loaders; nginx serves the big files over HTTP at 10G.
#
# Stateless anycast: every node's Kea has IDENTICAL static reservations (node eno1
# MAC -> fixed 402 IP), so whichever node answers offers the same address — no
# Kea-HA / shared lease DB needed.
#
# `netbootDir` (the built kernel+initrd+netboot.ipxe) is passed via specialArgs
# from the node flake (installer flake's `packages.netboot`).
#
{ config, lib, pkgs, netbootDir, ... }:

let
  anycastVip = "10.241.10.20";            # PXE service + TFTP next-server + HTTP host
  provSubnet = "10.242.10.0/24";          # provisioning VLAN 402 (routed SVI on the ToRs)
  httpBase   = "http://${anycastVip}";    # nginx vhost below
  tftpRoot   = "/var/lib/atftp";

  # Per-node eno1 MAC -> fixed 402 IP. IDENTICAL on every node (stateless anycast).
  # Add super-b / super-c MACs once known (read from the Kea lease log on first PXE,
  # or `cat /sys/class/net/eno1/address` in the netboot installer).
  reservations = [
    { hw-address = "ac:1f:6b:15:d8:80"; ip-address = "10.242.10.10"; hostname = "super-a"; }
    { hw-address = "ac:1f:6b:15:d8:5a"; ip-address = "10.242.10.11"; hostname = "super-b"; }  # lan1/eno1 (seen PXE-ing 2026-09-05)
    # { hw-address = "??:??:??:??:??:??"; ip-address = "10.242.10.12"; hostname = "super-c"; }
    { hw-address = "0c:c4:7a:9d:47:e4"; ip-address = "10.242.10.13"; hostname = "super-d"; }
  ];
in
{
  # ---------------------------------------------------------------------------
  # Stage the tiny iPXE loaders (TFTP) + expose the netboot dir path for nginx.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d ${tftpRoot} 0755 atftpd atftpd - -"
    "L+ ${tftpRoot}/undionly.kpxe - - - - ${pkgs.ipxe}/undionly.kpxe"
    "L+ ${tftpRoot}/ipxe.efi      - - - - ${pkgs.ipxe}/ipxe.efi"
  ];

  users.users.atftpd = { isSystemUser = true; group = "atftpd"; home = "/nonexistent"; createHome = false; };
  users.groups.atftpd = {};

  # ---------------------------------------------------------------------------
  # TFTP — serves ONLY the ~1MB iPXE loaders (undionly.kpxe / ipxe.efi).
  # ---------------------------------------------------------------------------
  services.atftpd = {
    enable = true;
    root = tftpRoot;
    extraOptions = [
      "--bind-address ${anycastVip}"   # the anycast VIP (relayed/routed reach)
      "--user atftpd.atftpd"
      "--maxthread 20"
      "--prevent-sas"
      "--logfile -"
    ];
  };
  systemd.services.atftpd = {
    after = [ "service-loopbacks.service" ];   # the anycast /32 must exist first
    wants = [ "service-loopbacks.service" ];
  };

  # ---------------------------------------------------------------------------
  # HTTP (the fast path) — nginx vhost bound to the anycast VIP only, serving the
  # netboot dir (netboot.ipxe + bzImage + initrd) and the HTTP-Boot ipxe.efi.
  # nginx-anycast.nix binds only 160.72.197.238, so no collision.
  # ---------------------------------------------------------------------------
  services.nginx.enable = true;
  services.nginx.virtualHosts."pxe" = {
    listenAddresses = [ anycastVip ];
    default = false;
    locations."/" = {
      root = netbootDir;              # bzImage + initrd + netboot.ipxe (relative refs)
      extraConfig = "autoindex on; sendfile on; tcp_nopush on;";
    };
    # UEFI HTTP-Boot clients ask for /ipxe.efi over HTTP.
    locations."= /ipxe.efi".alias = "${pkgs.ipxe}/ipxe.efi";
  };
  systemd.services.nginx = {
    after = [ "service-loopbacks.service" ];
    wants = [ "service-loopbacks.service" ];
  };

  # ---------------------------------------------------------------------------
  # Kea DHCP4 — authoritative for the 402 provisioning subnet, HTTP-first PXE
  # client-classing, identical static reservations, listening on the anycast VIP.
  # Serves RELAYED (unicast) requests from the ToR SVI, so socket type = udp.
  # ---------------------------------------------------------------------------
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      valid-lifetime = 3600;
      authoritative = true;
      interfaces-config = {
        # Receive on the anycast VIP (dummy1). ALSO open a socket on bond0.401: the
        # OFFER to a RELAYED client is a unicast back to the giaddr (the ToR VLAN402
        # SVI 10.242.10.x), which the kernel routes OUT bond0.401 — and Kea can only
        # transmit on an interface where it holds a socket. Without bond0.401 here the
        # reply fails with "Interface bond0.401 does not have any suitable IPv4 sockets
        # open" (RX works, TX silently drops). No subnet4 matches 10.241.10.x, so the
        # extra socket never offers anything on the data VLAN — it's TX-only in practice.
        interfaces = [ "dummy1/${anycastVip}" "bond0.401" ];
        dhcp-socket-type = "udp";                    # relayed = unicast
      };
      lease-database = { type = "memfile"; persist = true; name = "/var/lib/kea/kea-leases4.csv"; };
      control-socket = { socket-type = "unix"; socket-name = "/run/kea/kea4-ctrl-socket"; };

      # Boot classing — HTTP wherever possible; TFTP only for the tiny iPXE loader.
      #
      # Robust to ANY UEFI client-arch (option 93): the X10 AMI UEFI PXE ROM sends
      # 0x0009 (EFI x86-64), NOT the 0x0007 (EFI BC) that a narrow test assumes — so
      # matching one specific arch means NO class hits, Kea offers an IP with NO
      # bootfile, and the ROM gives up and falls through to the next boot device (USB).
      # Instead: gate on the "PXEClient" vendor-class (option 60, set by every PXE ROM,
      # BIOS or UEFI), single out iPXE / UEFI-HTTP / legacy-BIOS, and treat EVERYTHING
      # ELSE that is a PXEClient as UEFI-PXE → TFTP ipxe.efi. That last bucket catches
      # 0x0006/0x0007/0x0009/0x000b without enumerating them. A booted OS's dhclient has
      # no "PXEClient" option 60 → matches nothing → gets no bootfile (correct).
      client-classes = [
        # Already running iPXE (chainloaded) → hand the HTTP netboot script (kernel+initrd HTTP).
        { name = "ipxe"; test = "substring(option[77].hex,0,4) == 'iPXE'";
          boot-file-name = "${httpBase}/netboot.ipxe"; }
        # Any PXE ROM (BIOS or UEFI) advertises vendor-class "PXEClient:Arch:NNNNN:...".
        { name = "pxeclient"; test = "substring(option[60].text,0,9) == 'PXEClient'"; }
        # UEFI HTTP Boot firmware (arch 0x000f/0x0010) → fetch iPXE itself over HTTP (no TFTP).
        { name = "uefihttp";
          test = "member('pxeclient') and not member('ipxe') and (option[93].hex == 0x0010 or option[93].hex == 0x000f)";
          boot-file-name = "${httpBase}/ipxe.efi"; }
        # Legacy BIOS PXE (arch 0x0000) → TFTP undionly.kpxe, which then does HTTP.
        { name = "biospxe";
          test = "member('pxeclient') and not member('ipxe') and option[93].hex == 0x0000";
          boot-file-name = "undionly.kpxe"; next-server = anycastVip; }
        # Everything else that's a PXEClient = UEFI PXE (any x86-64/ia32/arm arch) →
        # TFTP the iPXE EFI loader, which then chainloads over HTTP.
        { name = "uefipxe";
          test = "member('pxeclient') and not member('ipxe') and not member('uefihttp') and not member('biospxe')";
          boot-file-name = "ipxe.efi"; next-server = anycastVip; }
      ];

      subnet4 = [{
        id = 402;
        subnet = provSubnet;
        # Small dynamic pool for as-yet-unreserved MACs (look up the lease by MAC).
        pools = [ { pool = "10.242.10.50 - 10.242.10.99"; } ];
        option-data = [ { name = "routers"; data = "10.242.10.1"; } ];   # VRRP SVI VIP
        reservations = reservations;
      }];
    };
  };
  systemd.services.kea-dhcp4-server = {
    after = [ "service-loopbacks.service" ];
    wants = [ "service-loopbacks.service" ];
    serviceConfig.MemoryMax = "128M";
  };
}
