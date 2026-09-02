#
# ~/nixos/super/super-d/pxe.nix — anycast PXE/netboot server for the super nodes.
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
    # { hw-address = "??:??:??:??:??:??"; ip-address = "10.242.10.11"; hostname = "super-b"; }
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
        interfaces = [ "dummy1/${anycastVip}" ];   # bind the anycast VIP (relayed reach)
        dhcp-socket-type = "udp";                    # relayed = unicast
      };
      lease-database = { type = "memfile"; persist = true; name = "/var/lib/kea/kea-leases4.csv"; };
      control-socket = { socket-type = "unix"; socket-name = "/run/kea/kea4-ctrl-socket"; };

      # Boot classing — HTTP wherever possible; TFTP only for the tiny iPXE loader.
      client-classes = [
        # Already running iPXE → hand the HTTP netboot script (kernel+initrd over HTTP).
        { name = "ipxe";  test = "substring(option[77].hex,0,4) == 'iPXE'";
          boot-file-name = "${httpBase}/netboot.ipxe"; }
        # UEFI HTTP Boot firmware → fetch iPXE itself over HTTP (no TFTP).
        { name = "uefihttp"; test = "not member('ipxe') and option[93].hex == 0x0010";
          boot-file-name = "${httpBase}/ipxe.efi"; }
        # UEFI PXE → TFTP the iPXE EFI loader, which then does HTTP.
        { name = "uefipxe"; test = "not member('ipxe') and option[93].hex == 0x0007";
          boot-file-name = "ipxe.efi"; next-server = anycastVip; }
        # Legacy BIOS PXE → TFTP undionly.kpxe, which then does HTTP.
        { name = "biospxe"; test = "not member('ipxe') and option[93].hex == 0x0000";
          boot-file-name = "undionly.kpxe"; next-server = anycastVip; }
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
