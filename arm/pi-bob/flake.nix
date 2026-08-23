#
# arm/pi-bob/flake.nix
#
# NixOS config for a Raspberry Pi 5 SD-card image for Bob (iperf2 maintainer),
# so he can try NixOS on his Pi. Pi-specific support (kernel, firmware,
# bootloader, vendor pkgs) comes from nixos-raspberrypi. Modeled on ../pi5-1,
# but SD-card-only (no NVMe, stock kernel) and split into small ./nix/ modules.
#
# This is a DEMO card for a lab: it ships deliberately weak, obvious-to-change
# passwords (see nix/users.nix / nix/sshd.nix).
#
# ---------------------------------------------------------------------------
# Targets and the commands to build / rebuild them
# ---------------------------------------------------------------------------
# This flake exposes three nixosConfigurations:
#   - pi-bob          the running system (native aarch64 deploy target).
#   - pi-bob-cross    the same system, cross-compiled from x86_64 for fast PC
#                     builds you push to the Pi (no on-Pi/QEMU compiling).
#   - pi-bob-sdimage  the same system, packaged as a flashable SD-card image
#                     (adds the sd-image module + cross-compile from x86_64).
#
# 1) Build the flashable SD-card image (cross-compiled x86_64 -> aarch64, no
#    QEMU/binfmt needed). Output lands in ./result/sd-image/*.img.zst:
#      nix build .#nixosConfigurations.pi-bob-sdimage.config.system.build.sdImage
#
#    Then flash it (double-check the /dev/sdX device!):
#      zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=10MB status=progress conv=fsync
#
# 2) Cross-compile on this PC and push to a running Pi (no re-flash; built here
#    at native x86 speed, activated on the Pi - best when a package isn't in the
#    aarch64 cache, e.g. grafana/prometheus, so the Pi never compiles it):
#      nixos-rebuild switch --flake .#pi-bob-cross --target-host root@pi-bob.local
#
# 3) Rebuild ON the Pi itself (native aarch64). A writable copy of this config
#    is seeded to ~/pi-bob on first boot (see nix/seed-config.nix), so on the Pi:
#      sudo nixos-rebuild switch --flake ~/pi-bob#pi-bob
#
# Handy variants:
#   - Just evaluate/type-check everything (no build):   nix flake check
#   - Build the system closure without an image:
#       nix build .#nixosConfigurations.pi-bob.config.system.build.toplevel
#   - Update the flake inputs (e.g. newer kernel):       nix flake update
#
{
  description = "pi-bob - Raspberry Pi 5 NixOS demo card for Bob";

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
      # Match the nixpkgs release that nixos-raspberrypi/main currently pins
      # (26.05) to avoid a home-manager/nixpkgs version-skew warning.
      url = "github:nix-community/home-manager/release-26.05";
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
      # SD-card image below. All the machine detail lives under ./nix/.
      baseModules = [
        ./nix/configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          # Per-user home configs. Each imports the shared baseline in
          # nix/home-common.nix and can be tweaked independently.
          home-manager.users.bob = import ./nix/home-bob.nix;
          home-manager.users.sebastian = import ./nix/home-sebastian.nix;
          home-manager.users.das = import ./nix/home-das.nix;
        }
      ];
    in
    {
      nixosConfigurations = {
        # The running system. Deploy with:
        #   nixos-rebuild switch --flake .#pi-bob --target-host root@pi-bob.local
        pi-bob = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = baseModules;
        };

        # The same running system as pi-bob, but cross-compiled from x86_64 so
        # it builds fast on a big PC instead of on the Pi. Push it to a running
        # Pi over SSH (builds here, activates there):
        #   nixos-rebuild switch --flake .#pi-bob-cross --target-host root@pi-bob.local
        # Useful when a package isn't in the aarch64 binary cache (e.g. a fresh
        # grafana/prometheus), so the Pi would otherwise compile it from source.
        pi-bob-cross = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = baseModules ++ [
            { nixpkgs.buildPlatform = "x86_64-linux"; }
          ];
        };

        # Same system packaged as a flashable SD-card image.
        # `nixpkgs.buildPlatform` cross-compiles it from x86_64-linux, so it
        # builds without binfmt/QEMU emulation. Build the image with:
        #   nix build .#nixosConfigurations.pi-bob-sdimage.config.system.build.sdImage
        pi-bob-sdimage = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = baseModules ++ [
            nixos-raspberrypi.nixosModules.sd-image
            { nixpkgs.buildPlatform = "x86_64-linux"; }
          ];
        };
      };
    };
}
