{
  description = ''
    Examples of NixOS systems' configuration for Raspberry Pi boards
    using nixos-raspberrypi
  '';

  nixConfig = {
    bash-prompt = "\[nixos-raspberrypi-demo\] ➜ ";
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };

    disko = {
      # the fork is needed for partition attributes support
      url = "github:nvmd/disko/gpt-attrs";
      # url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
    };
  };

  outputs = { self, nixpkgs
            , nixos-raspberrypi, disko
            , nixos-anywhere, ... }@inputs: let
    allSystems = nixpkgs.lib.systems.flakeExposed;
    forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);
  in {

    devShells = forSystems allSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          nil # lsp language server for nix
          nixpkgs-fmt
          nix-output-monitor
          nixos-anywhere.packages.${system}.default
        ];
      };
    });

    nixosConfigurations = let

      users-config-stub = {
        # This is identical to what nixos installer does in
        # (modulesPash + "profiles/installation-device.nix")

        # Use less privileged nixos user
        users.users.nixos = {
          isNormalUser = true;
          extraGroups = [
            "wheel"
            "networkmanager"
            "video"
          ];
          # Allow the graphical user to login without password
          initialHashedPassword = "";
        };

        # Allow the user to log in as root without a password.
        users.users.root.initialHashedPassword = "";

        # Don't require sudo/root to `reboot` or `poweroff`.
        security.polkit.enable = true;

        # Allow passwordless sudo from nixos user
        security.sudo = {
          enable = true;
          wheelNeedsPassword = false;
        };

        # Automatically log in at the virtual consoles.
        services.getty.autologinUser = "nixos";

        # We run sshd by default. Login is only possible after adding a
        # password via "passwd" or by adding a ssh key to ~/.ssh/authorized_keys.
        # The latter one is particular useful if keys are manually added to
        # installation device for head-less systems i.e. arm boards by manually
        # mounting the storage in a different system.
        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "yes";
        };

        # allow nix-copy to live system
        nix.settings.trusted-users = [ "nixos" ];
      };

      common-user-config = {config, pkgs, ... }: {
        imports = [
          ./modules/nice-looking-console.nix
          users-config-stub
        ];

        time.timeZone = "UTC";
        networking.hostName = "rpi${config.boot.loader.raspberryPi.variant}-demo";

        services.udev.extraRules = ''
          # Ignore partitions with "Required Partition" GPT partition attribute
          # On our RPis this is firmware (/boot/firmware) partition
          ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
            ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
            ENV{UDISKS_IGNORE}="1"
        '';

        environment.systemPackages = with pkgs; [
          tree
        ];


        # users.users.nixos.openssh.authorizedKeys.keys = [
        #   # YOUR SSH PUB KEY HERE #

        # ];
        # users.users.root.openssh.authorizedKeys.keys = [
        #   # YOUR SSH PUB KEY HERE #

        # ];


        system.nixos.tags = let
          cfg = config.boot.loader.raspberryPi;
        in [
          "raspberry-pi-${cfg.variant}"
          cfg.bootloader
          config.boot.kernelPackages.kernel.version
        ];
      };
    in {

      rpi02 = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-02.base
              usb-gadget-ethernet
              # config.txt example
              ./pi02-configtxt.nix
            ];
          })
          # Disk configuration
          # Assumes the system will continue to reside on the installation media (sd-card),
          # as there're hardly other feasible options on RPi02.
          # (see also https://github.com/nvmd/nixos-raspberrypi/issues/8#issuecomment-2804912881)
          # `sd-image` has lots of dependencies unnecessary for the installed system,
          # replicating its disk layout
          ({ config, pkgs, ... }: {
            fileSystems = {
              "/boot/firmware" = {
                device = "/dev/disk/by-label/FIRMWARE";
                fsType = "vfat";
                options = [
                  "noatime"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=1min"
                ];
              };
              "/" = {
                device = "/dev/disk/by-label/NIXOS_SD";
                fsType = "ext4";
                options = [ "noatime" ];
              };
            };
          })
          # Further user configuration
          common-user-config
          ({ config, pkgs, ... }: {
            environment.systemPackages = with pkgs; [
              i2c-tools
            ];
          })
        ];
      };

      rpi4 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, disko, ... }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-4.base
              raspberry-pi-4.display-vc4
              raspberry-pi-4.bluetooth
            ];
          })
          # Disk configuration
          disko.nixosModules.disko
          # WARNING: formatting disk with disko is DESTRUCTIVE, check if
          # `disko.devices.disk.main.device` is set correctly!
          ./disko-usb-btrfs.nix
          # Further user configuration
          common-user-config
          {
            boot.tmp.useTmpfs = true;
          }
        ];
      };

      rpi5 = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, disko, ... }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-5.base
              raspberry-pi-5.display-vc4
              ./pi5-configtxt.nix
            ];
          })
          # Disk configuration
          disko.nixosModules.disko
          # WARNING: formatting disk with disko is DESTRUCTIVE, check if
          # `disko.devices.disk.nvme0.device` is set correctly!
          ./disko-nvme-zfs.nix
          { networking.hostId = "8821e309"; } # NOTE: for zfs, must be unique
          # Further user configuration
          common-user-config
          {
            boot.tmp.useTmpfs = true;
          }

          # Advanced: Use non-default kernel from kernel-firmware bundle
          ({ config, pkgs, lib, ... }: let
            kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
          in {
            boot = {
              loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
              kernelPackages = kernelBundle.linuxPackages_rpi5;
            };

            nixpkgs.overlays = lib.mkAfter [
              (self: super: {
                # This is used in (modulesPath + "/hardware/all-firmware.nix") when at least
                # enableRedistributableFirmware is enabled
                # I know no easier way to override this package
                inherit (kernelBundle) raspberrypiWirelessFirmware;
                # Some derivations want to use it as an input,
                # e.g. raspberrypi-dtbs, omxplayer, sd-image-* modules
                inherit (kernelBundle) raspberrypifw;
              })
            ];
          })

        ];
      };

    };

  };
}