{
  description = "t Flake";

  # https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # https://docs.github.com/en/rest/branches/branches?apiVersion=2022-11-28#get-a-branch
    # nixpkgs-unstable.url = "github:randomizedcoder/nixpkgs/8f146535307f0168d758fe6fee6f52663cb11695";#iperf2_2.2.1
    # nixpkgs-unstable.url = "github:randomizedcoder/nixpkgs/c9580e24eb621d72eda63355d7c8dbfb1654d333";
    # https://github.com/NixOS/nix/issues/12022
    #nix flake lock --override-input nixpkgs /home/eelco/Dev/nixpkgs
    #nix flake lock --override-input nixpkgs "/home/das/Downloads/nixpkgs
    #nixpkgs.url = "/home/das/Downloads/nixpkgs";
    #nixpkgs = "../../../Downloads/nixpkgs/";
    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      # https://github.com/hyprwm/hyprland-plugins
      inputs.hyprland.follows = "hyprland";
    };
  };

  #outputs = inputs@{ nixpkgs, home-manager, hyprland, ... }:
  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, hyprland, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      # https://nixos.wiki/wiki/Flakes#Importing_packages_from_multiple_channels
      # overlay-unstable = final: prev: {
      #   unstable = nixpkgs-unstable.legacyPackages.${prev.system};
      # };
      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config = { allowUnfree = true; };
        };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations = {
      t = lib.nixosSystem rec {
        #system ="x86_64-linux";
        inherit system;
        specialArgs = { inherit hyprland; };
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unstable ]; })
          ./configuration.nix
          hyprland.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.das = import ./home.nix;
            home-manager.extraSpecialArgs = specialArgs;
            # see also: https://github.com/HeinzDev/Hyprland-dotfiles/blob/main/flake.nix
          }
        ];
      };
    };
  };
}
