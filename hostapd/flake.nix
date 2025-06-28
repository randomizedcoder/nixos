#
# nixos/hostapd/flake.nix
#
{
  description = "NixOS with hostapd 2.10 + patch";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosConfigurations.l2 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [
          (final: prev: {
            hostapd = prev.hostapd.overrideDerivation (old: {
              version = "2.10";
              src = final.fetchurl {
                url = "https://w1.fi/releases/hostapd-2.10.tar.gz";
                sha256 = "0pcik0a6yin9nib02frjhaglmg44hwik086iwg1751b7kdwpqvi0";
              };
              patches = (old.patches or []) ++ [
                (final.fetchpatch {
                  url = "https://tildearrow.org/storage/hostapd-2.10-lar.patch";
                  sha256 = "USiHBZH5QcUJfZSxGoFwUefq3ARc4S/KliwUm8SqvoI=";
                })
              ];
            });
          })
        ];
        config.allowUnfree = true;
      };

      modules = [
        ({ config, pkgs, ... }: {
          environment.systemPackages = [ pkgs.hostapd ];
          services.hostapd.enable = false;
        })
      ];
    };
  };
}

# end