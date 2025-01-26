{
  description = "Base system for raspberry pi 5";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:
  {
    nixosModules = {
      system = {
        disabledModules = [
          "profiles/base.nix"
        ];

        system.stateVersion = "24.11";
      };
      users = {
        users.users = {
          das = {
            password = "admin123";
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
            ];
          };
        };
      };
    };

    packages.aarch64-linux = {
      sdcard = nixos-generators.nixosGenerate {
        system = "aarch64-linux";
        format = "sd-aarch64";
        modules = [
          ./extra-config.nix
          self.nixosModules.system
          self.nixosModules.users
          ( { ... }: {
            config = {
              sdImage.compressImage = false;
            };
          })
        ];
      };
    };
  };
}

