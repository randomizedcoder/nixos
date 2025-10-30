#
# nixos/chromebox/chromebox2/flake.nix
#
# example
# https://github.com/nix-community/nixos-anywhere-examples/blob/main/flake.nix
#
{
  description = "chromebox2 Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";

    };
    # https://github.com/nix-community/disko/
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    # https://gitlab.com/luxzeitlos/k8nix - Kubernetes addon management
    k8nix.url = "gitlab:luxzeitlos/k8nix";
    k8nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, disko, home-manager, k8nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations.chromebox2 =  nixpkgs.lib.nixosSystem {
      system ="x86_64-linux";
      #inherit system;
      modules = [
        disko.nixosModules.disko
        #./hardware-configuration.nix
        ./configuration.nix
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
}
