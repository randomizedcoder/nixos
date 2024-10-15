{
  description = "NixOS in MicroVMs";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm, ... }@inputs:
    let
      system = "x86_64-linux";
    in {
      packages.${system} = {
        default = self.packages.${system}.my-microvm;
        my-microvm = self.nixosConfigurations.my-microvm.config.microvm.declaredRunner;
      };

      nixosConfigurations = {
        my-microvm = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            microvm.nixosModules.microvm

            ({pkgs, ... }:{
              networking.hostName = "my-microvm";
              users.users.root.password = "test";

              microvm = {
                volumes = [
                  {
                    mountPoint = "/var";
                    image = "var.img";
                    size = 256;
                  }
                  {
                    mountPoint = "/nix/var";
                    image = "nix.var.img";
                    size = 256;
                  }
                ];

                shares = [ {
                  # use "virtiofs" for MicroVMs that are started by systemd
                  proto = "9p";
                  tag = "ro-store";
                  # a host's /nix/store will be picked up so that no
                  # squashfs/erofs will be built for it.
                  source = "/nix/store";
                  mountPoint = "/nix/.ro-store";
                } ];

                # https://astro.github.io/microvm.nix/interfaces.html
                interfaces = [ {
                  type = "user";
                  id = "vm-a1";
                  # Locally administered have one of 2/6/A/E in the second nibble.
                  mac = "02:00:00:00:00:01";
                } ];

                # https://astro.github.io/microvm.nix/options.html
                hypervisor = "qemu";
                mem = 2048;
                vcpu = 2;
                socket = "control.socket";
              };

              users.users.das = {
                isNormalUser = true;
                description = "das";
                extraGroups = [ "wheel" ];
                initialPassword = "test";
                # packages = with pkgs; [
                # ];
                # https://nixos.wiki/wiki/SSH_public_key_authentication
                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
                ];
              };

              environment.systemPackages = with pkgs; [ cowsay htop ];

              services.openssh = {
                enable = true;
              };
              services.qemuGuest.enable = true;

              system.stateVersion = "24.05";

            })
          ];
        };
      };
    };
}
