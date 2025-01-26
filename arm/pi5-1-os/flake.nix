{
  description = "pi5-1 Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    raspberry-pi-nix.url = "github:nix-community/raspberry-pi-nix";

    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, raspberry-pi-nix, home-manager, ... }:
    let
      #system = "x86_64-linux";
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      lib = nixpkgs.lib;
      basic-config = { pkgs, lib, ... }: {
        # bcm2711 for rpi 3, 3+, 4, zero 2 w
        # bcm2712 for rpi 5
        # See the docs at:
        # https://www.raspberrypi.com/documentation/computers/linux_kernel.html#native-build-configuration
        raspberry-pi-nix.board = "bcm2712";
        networking = {
          hostName = "pi5-1";
        };
      };
    in {
    nixosConfigurations = {
      pi5-1 = lib.nixosSystem {
        #system ="x86_64-linux";
        inherit system;
        modules = [
          raspberry-pi-nix.nixosModules.raspberry-pi raspberry-pi-nix.nixosModules.sd-image basic-config
          ./configuration.nix
          # home-manager.nixosModules.home-manager
          # {
          #   home-manager.useGlobalPkgs = true;
          #   home-manager.useUserPackages = true;
          #   home-manager.users.das = import ./home.nix;

          #   # Optionally, use home-manager.extraSpecialArgs to pass
          #   # arguments to home.nix
          # }
        ];
      };
    };
  };
}
