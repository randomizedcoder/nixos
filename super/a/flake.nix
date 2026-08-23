{
  # NFB LADC Supermicro node (super-a/b/d). Byte-identical on every node: the hostname
  # comes from ./host.nix, so the only per-node files are host.nix + hardware-configuration.nix.
  # Build/deploy with:  sudo nixos-rebuild switch --flake ~/nixos/super/<x>#super
  description = "NFB LADC Supermicro node — LACP bond + VLAN401 + BGP/ECMP/RTBH routing";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.super = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };
    };
}
