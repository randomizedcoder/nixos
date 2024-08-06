# Example flake.nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }: {
    emulated-dev = nixpkgs.lib.nixosSystem {
      # host system
      system = "x86_64-linux";
      modules = let
        #guestSystem = "aarch64-unknown-linux-gnu";
        # you can use packages in the guest machine with cross system configuration
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          #crossSystem.config = guestSystem;
        };
      in [
        #{ nixpkgs.crossSystem.config = guestSystem; }

        microvm.nixosModules.microvm
        {
          networking.hostName = "my-microvm";
          microvm = {
            # you can choose what CPU will be emulated by qemu
            #cpu = "cortex-a53";
            mem = 2048;
            vcpu = 2;
            hypervisor = "qemu";
          };
          environment.systemPackages = with pkgs; [ cowsay htop ];
          services.getty.autologinUser = "root";
          system.stateVersion = "24.05";
        }
      ];
    };
  };
}
