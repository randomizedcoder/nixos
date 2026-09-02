{
  # NFB super-node custom installers.
  #
  #   * Per-node ISOs (iso-a..d)     — LACP bond + VLAN 401 + the node's real data
  #     IP, for USB/vmedia boot. (Legacy fallback; PXE netboot below is preferred.)
  #   * Shared PXE netboot image     — ONE image for every node: a single untagged
  #     `eno1` on the provisioning VLAN 402 via DHCP (no bond, no VLAN 401). Served
  #     anycast from super-* by `~/nixos/super/pxe.nix` (Kea+atftpd+nginx). The
  #     installed system sets up the bond/VLAN 401 itself; per-node identity comes
  #     from the DHCP reservation, and the config is chosen at nixos-anywhere time.
  #
  # Build:  nix build ~/nixos/super/installer#iso-a        (…#iso-b/-c/-d)
  #         nix build ~/nixos/super/installer#netboot       → bzImage + initrd + netboot.ipxe
  # The netboot result is served by super-d over HTTP/TFTP (see pxe.nix).
  description = "NFB super-node installers — per-node ISOs + a shared PXE netboot image + storcli/zfs/disko";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      # Per-node identity: data IP (VLAN 401) + ZFS hostId (matches host.nix).
      nodes = {
        a = { ip = "10.241.10.10"; hostId = "0a51a001"; };
        b = { ip = "10.241.10.11"; hostId = "0b52b002"; };
        c = { ip = "10.241.10.12"; hostId = "0c53c003"; };
        d = { ip = "10.241.10.13"; hostId = "0d54d004"; };
      };

      dasKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t";

      # ---- shared installer config (base-module + network agnostic) -----
      # Everything EXCEPT the base installer module (cd-dvd vs netboot) and the
      # network stanza — those differ between the ISO and netboot variants.
      commonModule = { config, pkgs, lib, ... }: {
        # kernel + stage-1 on local VGA (tty0) AND the Supermicro SOL (ttyS1/COM2),
        # so the whole boot is visible over IPMI SOL with no browser/iKVM.
        boot.kernelParams = [ "console=tty0" "console=ttyS1,115200n8" ];
        boot.kernelModules = [ "bonding" "8021q" "ixgbe" ];

        # Drop docs + external firmware (X540/ixgbe + LSI SAS3108 + SATADOM need none).
        documentation.enable = false;
        documentation.man.enable = false;
        documentation.nixos.enable = false;
        hardware.enableRedistributableFirmware = lib.mkForce false;
        hardware.enableAllFirmware = lib.mkForce false;

        # root SSH (for nixos-anywhere / manual install).
        services.openssh.enable = true;
        services.openssh.settings.PermitRootLogin = "prohibit-password";
        users.users.root.openssh.authorizedKeys.keys = [ dasKey ];

        # Storage build + install tools.
        boot.supportedFilesystems = [ "zfs" ];
        nixpkgs.config.allowUnfree = true;   # storcli is unfree
        environment.systemPackages = with pkgs; [
          storcli gptfdisk util-linux   # blkdiscard is in util-linux
          zfs disko
        ];
        environment.etc."storcli-90pct-vds.sh" = {
          source = ./storcli-90pct-vds.sh;
          mode = "0755";
        };

        system.stateVersion = "26.05";
      };

      # ---- per-node ISO variant (USB/vmedia; LACP bond + VLAN401 + node IP) ---
      mkIso = letter: node:
        lib.nixosSystem {
          inherit system;
          modules = [
            (
              { config, pkgs, modulesPath, lib, ... }:
              {
                imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
                networking.hostName = "super-inst-${letter}";
                networking.hostId = node.hostId;
                networking.useDHCP = false;
                networking.bonds.bond0 = {
                  interfaces = [ "eno1" "eno2" ];
                  driverOptions = { mode = "802.3ad"; lacp_rate = "fast"; miimon = "100"; xmit_hash_policy = "layer3+4"; };
                };
                networking.vlans.vlan401 = { id = 401; interface = "bond0"; };
                networking.interfaces.vlan401.ipv4.addresses = [ { address = node.ip; prefixLength = 24; } ];
                networking.defaultGateway = "10.241.10.1";
                networking.nameservers = [ "10.201.10.1" ];
                # slim the ISO hard (must read reliably over flaky vmedia)
                system.extraDependencies = lib.mkForce [ ];
                isoImage.squashfsCompression = "xz -Xdict-size 100%";
                isoImage.isoBaseName = lib.mkForce "super-installer-${letter}";
              }
            )
            commonModule
          ];
        };

      # ---- shared PXE netboot variant -----------------------------------
      # ONE image served anycast to every node. Single untagged eno1 on the
      # provisioning VLAN 402 via DHCP (bring eno2 down; the `no lacp
      # suspend-individual` on the ToR lets the lone link forward). No bond, no
      # VLAN 401 — the *installed* system configures those.
      netbootSystem = lib.nixosSystem {
        inherit system;
        modules = [
          (
            { config, pkgs, modulesPath, lib, ... }:
            {
              imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];
              networking.hostName = "super-netboot";
              networking.hostId = "0e5eb007";                # installer only (no installed pool)
              networking.useDHCP = false;
              networking.interfaces.eno1.useDHCP = true;     # untagged → provisioning VLAN 402
              networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
            }
          )
          commonModule
        ];
      };
    in
    {
      nixosConfigurations =
        (lib.mapAttrs' (l: n: lib.nameValuePair "installer-${l}" (mkIso l n)) nodes)
        // { netboot = netbootSystem; };

      packages.${system} =
        (lib.mapAttrs' (l: n: lib.nameValuePair "iso-${l}" (mkIso l n).config.system.build.isoImage) nodes)
        // {
          # kernel (bzImage) + initrd + netboot.ipxe in one dir, for super-d to
          # serve over TFTP/HTTP. The netboot.ipxe references bzImage/initrd by
          # relative path, so serving this whole dir from one HTTP root works.
          netboot = pkgs.symlinkJoin {
            name = "super-netboot";
            paths = [
              netbootSystem.config.system.build.netbootRamdisk
              netbootSystem.config.system.build.kernel
              netbootSystem.config.system.build.netbootIpxeScript
            ];
          };
        };
    };
}
