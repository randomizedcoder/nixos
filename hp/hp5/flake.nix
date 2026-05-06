{
  description = "HP5 Flake";

  inputs = {
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
    # After pushing new xdp2 changes, refresh on hp5 with:
    #   nix flake update xdp2 && sudo nixos-rebuild switch --flake .#hp5
    xdp2 = {
      url = "github:randomizedcoder/xdp2/xdp2-rs";
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
      hp5 = lib.nixosSystem {
        #system ="x86_64-linux";
        inherit system;
        modules = [
          ./configuration.nix
          xdp2.nixosModules.physical-testbed
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.das = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
        ];
      };
    };
  };
}
