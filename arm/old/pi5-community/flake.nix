{
  description = "raspberry-pi-nix example";
  #nixConfig = {
  #  # Only during the first build, otherwise I don't want to allow such a binary cache
  #  extra-substituters = [ "https://nix-community.cachix.org" ];
  #  extra-trusted-public-keys = [
  #    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  #  ];
  #};

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    raspberry-pi-nix.url = "github:nix-community/raspberry-pi-nix";
  };

  outputs = { self, nixpkgs, raspberry-pi-nix }:
    let
      inherit (nixpkgs.lib) nixosSystem;
      basic-config = { pkgs, lib, ... }: {
        # bcm2711 for rpi 3, 3+, 4, zero 2 w
        # bcm2712 for rpi 5
        # See the docs at:
        # https://www.raspberrypi.com/documentation/computers/linux_kernel.html#native-build-configuration
        raspberry-pi-nix.board = "bcm2712";

        time.timeZone = "America/Los_Angeles";

        users.users = {
          das = {
            password = "admin123";
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            # openssh.authorizedKeys.keys = [
            #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
            # ];
          };
        };

        networking = {
          hostName = "myrpi5";
          #useDHCP = false;
          #interfaces = { wlan0.useDHCP = true; };
        };

        environment.systemPackages = with pkgs; [
          emacs
          git
          wget
          # bluez
          # bluez-tools
        ];

        services.openssh.enable = true;

        #services.lldpd.enable = true;

        # hardware = {
        #   bluetooth.enable = true;
        #   # TODO: check if needed
        #   # raspberry-pi = {
        #   #   config = {
        #   #     all = {
        #   #       base-dt-params = {
        #   #         # enable autoprobing of bluetooth driver
        #   #         # https://github.com/raspberrypi/linux/blob/c8c99191e1419062ac8b668956d19e788865912a/arch/arm/boot/dts/overlays/README#L222-L224
        #   #         krnbt = {
        #   #           enable = true;
        #   #           value = "on";
        #   #         };
        #   #       };
        #   #     };
        #   #   };
        #   # };
        # };
        system.stateVersion = "24.11";
      };

    in
      {
        nixosConfigurations = {
          myrpi5 = nixosSystem {
            system = "aarch64-linux";
            modules = [
              raspberry-pi-nix.nixosModules.raspberry-pi raspberry-pi-nix.nixosModules.sd-image  basic-config

              {
                # https://nixos-and-flakes.thiscute.world/development/cross-platform-compilation#cross-compilation
                # https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
                # https://nixos.org/manual/nixos/stable/options#opt-boot.binfmt.emulatedSystems
                nixpkgs.crossSystem.system = "aarch64-linux"; # "riscv64-linux"
              }
            ];
          };
        };
      };
}
