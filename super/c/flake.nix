{
  # NFB LADC Supermicro node (super-a..d). Per-node files: host.nix (hostname +
  # ZFS hostId), disko.nix (device by-ids + any extras), hardware-configuration.nix.
  # Shared, copied per node: disko-super.nix, zfs.nix, configuration.nix + modules.
  #
  # NOTE: super-c's configuration.nix is still the nixos-generate-config STUB — it
  # needs the full module set (networking/routing/firewall/etc.) copied from an
  # a/b/d node to reach parity before a real deploy. This flake wires storage only.
  #
  # Reinstall (WIPES disks via disko — run the storcli 90% VD pre-step first):
  #   nix run github:nix-community/nixos-anywhere -- \
  #     --flake ~/nixos/super/c#super --target-host root@<installer-ip>
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
    in {
      nixosConfigurations.super = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko.nix          # per-node: device by-ids + any extras
          ./zfs.nix            # ARC cap + ZFS services (data pool 'tank')
          ./configuration.nix
        ];
      };
    };
}
