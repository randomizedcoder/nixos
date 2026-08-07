{
  description = "HP1 Flake";

  inputs = {
    # Aligned with hp2/hp5 on nixos-unstable so all benchmark hosts run
    # matching kernels (xdp2 docs/physical-testbed.md §4).
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # xdp2 provides nixosModules.physical-testbed for the benchmark-host
    # tuning (kernel params, NIC ethtool, IRQ pinning, noise suppression).
    # See xdp2 docs/physical-testbed.md §5–§7.
    # After pushing new xdp2 changes, refresh on hp1 with:
    #   nix flake update xdp2 && sudo nixos-rebuild switch --flake .#hp1
    xdp2 = {
      # merge/matrix-physical-testbed carries the nic-tuning module
      # split (xdp2.nicTuning.driver option, mlx5_core branch). Flip
      # back to xdp2-rs / main once that branch is merged forward.
      url = "github:randomizedcoder/xdp2/merge/matrix-physical-testbed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, xdp2, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations = {
      hp1 = lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          xdp2.nixosModules.physical-testbed
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.das = import ./home.nix;
          }
        ];
      };
    };
  };
}
