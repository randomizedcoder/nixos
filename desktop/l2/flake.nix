#
# l2/flake.nix
#
{
  description = "l2 Flake";

  # https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";

      lib = nixpkgs.lib;

      overlays = {
        default = final: prev: {
          hostapd = prev.hostapd.overrideDerivation (old: {
            version = "2.10";
            src = final.fetchurl {
              url = "https://w1.fi/releases/hostapd-2.10.tar.gz";
              sha256 = "0pcik0a6yin9nib02frjhaglmg44hwik086iwg1751b7kdwpqvi0";
              # nix-prefetch-url https://w1.fi/releases/hostapd-2.10.tar.gz
            };
            patches = [
              (final.fetchpatch {
                url = "https://tildearrow.org/storage/hostapd-2.10-lar.patch";
                sha256 = "USiHBZH5QcUJfZSxGoFwUefq3ARc4S/KliwUm8SqvoI=";
              })
            ];
          });
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlays.default ];
        config.allowUnfree = true;
      };

    in {
      nixosConfigurations = {
        l2 = lib.nixosSystem {

          inherit system;

          modules = [
            ./configuration.nix
            {
              nixpkgs.pkgs = pkgs;
            }
            home-manager.nixosModules.home-manager
            {
              home-manager.useUserPackages = true;
              home-manager.users.das = { config, pkgs, ... }: {
                imports = [ ./home.nix ];
              };
            }
          ];
        };
      };
    };
}

# end