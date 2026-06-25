#
# Banana Pi F3 flake.nix
#
# Build (cross-compiled x86_64 -> riscv64):
#   nix build .#sdImage     # bootable SD image (default target; ./result/sd-image/*.img)
#   nix build .#uboot       # U-Boot blobs: FSBL.bin, bootinfo_emmc.bin, u-boot.itb
#   nix build .#opensbi     # OpenSBI fw_dynamic.itb
#   nix build .#nixosConfigurations.bpi-f3-nvme.config.system.build.toplevel  # NVMe-root system
#   nix flake check         # eval both configs + treefmt + statix
#   nix fmt                 # format the tree (nixfmt + deadnix; prettier for *.md)
#
# Flash the built image to the SD card (replace /dev/sdb with your card!):
# sudo umount /dev/sdb1 && sudo umount /dev/sdb2
# sudo dd if=$(readlink -f result/sd-image/*.img) of=/dev/sdb bs=4M conv=fsync status=progress; sync; sudo eject /dev/sdb
#
# NVMe needs to be wiped to retest the full insall process.  Once wiped, the boot happens via SD card,
# and then from SD the NVMe gets formatted and installed
# sudo bpi-f3-nvme-wipe
#
{
  description = "NixOS for the Banana Pi BPI-F3 (SpacemiT K1, RISC-V), cross-compiled from x86_64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Bootloader sources (non-flake), pinned via flake.lock.
    #
    # U-Boot is Armbian's fork + its patch set (see nix/pkgs/u-boot): the stock
    # vendor U-Boot can't extlinux-boot a generic distro, this can.
    uboot-spacemit = {
      url = "github:pyavitz/spacemit-u-boot/k1-bl-v2.2.9-release";
      flake = false;
    };
    # SpacemiT vendor OpenSBI (gitee), tag k1-bl-v2.2.10-release.
    opensbi-spacemit = {
      url = "git+https://gitee.com/spacemit-buildroot/opensbi.git?ref=k1-bl-v2.2.y&rev=34143f5f665be8b86ebb71b8085a1ade7f8b97ad";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      let
        overlay = import ./nix/overlay.nix inputs;

        # Cross pkgset: build host x86_64-linux -> target riscv64, with the
        # bootloader overlay. Built once and shared, so the overlay + crossSystem
        # are never applied twice.
        pkgsCross = import nixpkgs {
          localSystem = "x86_64-linux";
          crossSystem = import ./nix/cross.nix;
          overlays = [ overlay ];
        };

        # Modules shared by the SD-root and NVMe-root systems.
        commonModules = [
          { nixpkgs.pkgs = pkgsCross; }
          ./nix/modules
        ];

        # NVMe-root system: same as the SD system but with `/` on the NVMe.
        # Built ahead of the SD system so its toplevel can be shipped inside the
        # SD image (see nix/modules/nvme/provision.nix).
        nvmeSystem = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = commonModules ++ [ ./nix/modules/nvme/root.nix ];
        };
      in
      {
        systems = [ "x86_64-linux" ];
        imports = [ inputs.treefmt-nix.flakeModule ];

        flake = {
          overlays.default = overlay;

          nixosConfigurations = {
            # SD-root system (what the SD image boots). Carries the NVMe-root
            # toplevel + the `bpi-f3-nvme-install` migrator (nvme/provision.nix).
            bpi-f3-cross = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = {
                nvmeToplevel = nvmeSystem.config.system.build.toplevel;
              };
              modules = commonModules ++ [ ./nix/modules/nvme/provision.nix ];
            };

            # NVMe-root system. Switched into by `bpi-f3-nvme-install`; future
            # `nixos-rebuild`s on the device target this configuration.
            bpi-f3-nvme = nvmeSystem;
          };
        };

        perSystem =
          { pkgs, ... }:
          {
            packages = {
              default = inputs.self.nixosConfigurations.bpi-f3-cross.config.system.build.sdImage;
              sdImage = inputs.self.nixosConfigurations.bpi-f3-cross.config.system.build.sdImage;
              uboot = pkgsCross.bpi-f3-uboot;
              opensbi = pkgsCross.k1-opensbi;
            };

            # `nix fmt` + `nix flake check`'s formatting gate (nixfmt-rfc-style + deadnix).
            # prettier reflows Markdown prose (proseWrap=never -> let the renderer
            # soft-wrap; no hard line breaks). Scoped to *.md so it never touches
            # flake.lock or other files.
            treefmt = {
              projectRootFile = "flake.nix";
              programs = {
                nixfmt.enable = true;
                deadnix.enable = true;
                prettier = {
                  enable = true;
                  includes = [ "*.md" ];
                  settings.proseWrap = "never";
                };
              };
            };

            # `nix flake check` lint gate.
            checks.statix = pkgs.runCommandLocal "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
              statix check "${inputs.self}"
              touch "$out"
            '';

            devShells.default = pkgs.mkShellNoCC {
              packages = with pkgs; [
                nixfmt
                deadnix
                statix
                dtc
                nix-output-monitor
              ];
            };
          };
      }
    );
}
