#
# arm/pi4-1/flake.nix
#
# NixOS config for the Raspberry Pi 4 "pi4-1".
# Pi-specific support (kernel, firmware, bootloader, vendor pkgs) comes from
# nixos-raspberrypi. Modeled on ../../hp/hp5.
#
# Deploy onto the running installer SD card:
#   nixos-rebuild switch --flake .#pi4-1 --target-host root@<pi-ip>
#
{
  description = "pi4-1 - Raspberry Pi 4";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    # Keep home-manager's nixpkgs in lockstep with the one nixos-raspberrypi
    # pins, so we get cache hits and avoid version skew.
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixos-raspberrypi,
      home-manager,
      ...
    }:
    let
      # The actual machine config, shared by the deployable system and the
      # SD-card image below.
      baseModules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.das = import ./home.nix;
        }
      ];
    in
    {
      nixosConfigurations = {
        # The running system. Deploy with:
        #   nixos-rebuild switch --flake .#pi4-1 --target-host root@<pi-ip>
        pi4-1 = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = baseModules;
        };

        # Same system packaged as a flashable SD-card image.
        # `nixpkgs.buildPlatform` cross-compiles it from x86_64-linux, so it
        # builds without binfmt/QEMU emulation. Build the image with:
        #   nix build .#nixosConfigurations.pi4-1-sdimage.config.system.build.sdImage
        pi4-1-sdimage = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = baseModules ++ [
            nixos-raspberrypi.nixosModules.sd-image
            { nixpkgs.buildPlatform = "x86_64-linux"; }
          ];
        };
      };
    };
}
