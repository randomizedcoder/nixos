#
# nixos/qotom/nfb/flake.nix
#
# example
# https://github.com/nix-community/nixos-anywhere-examples/blob/main/flake.nix
#
{
  description = "nfbQotom Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    #nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      #url = "github:nix-community/home-manager/release-unstable"; # unstable doesn't seem to exist
      #url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";

    };
    # https://github.com/nix-community/disko/
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, disko, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      # overlay-unstable = final: prev: {
      #   unstable = import nixpkgs-unstable {
      #     inherit system;
      #     config = { allowUnfree = true; };
      #   };
      # };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations.nfbQotom =  nixpkgs.lib.nixosSystem {
      system ="x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.das = import ./home.nix;
        }
      ];
    };
  };
}
