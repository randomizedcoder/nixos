{
  # NFB LADC Supermicro node (super-a..d). Per-node files: host.nix (hostname +
  # ZFS hostId), disko.nix (device by-ids + any extras), hardware-configuration.nix.
  # Shared, copied per node: disko-super.nix, zfs.nix, configuration.nix + modules.
  #
  # Reinstall (WIPES disks via disko — run the storcli 90% VD pre-step first):
  #   nix run github:nix-community/nixos-anywhere -- \
  #     --flake ~/nixos/super/<x>#super --target-host root@<installer-ip>
  # Rebuild in place:  sudo nixos-rebuild switch --flake ~/nixos/super/<x>#super
  description = "NFB LADC Supermicro node — LACP bond + VLAN401 + BGP/ECMP/RTBH routing + ZFS data pool";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # https://github.com/nix-community/disko
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Build the shared PXE netboot installer image inline; pxe.nix serves it.
      netbootSys = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./netboot-installer.nix ];
      };
      netbootDir = pkgs.symlinkJoin {
        name = "super-netboot";
        paths = with netbootSys.config.system.build; [ netbootRamdisk kernel netbootIpxeScript ];
      };
    in {
      nixosConfigurations.super = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit netbootDir; };   # -> pxe.nix
        modules = [
          disko.nixosModules.disko
          ./disko.nix          # per-node: device by-ids + any extras
          ./zfs.nix            # ARC cap + ZFS services (data pool 'tank')
          ./configuration.nix
        ];
      };
    };
}
