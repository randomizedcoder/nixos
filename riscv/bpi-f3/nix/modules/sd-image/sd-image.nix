# `nixos/modules/installer/sd-card/sd-image.nix` patched for SpacemiT K1 boards.
#
#  https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/sd-card/sd-image.nix
#
# The K1 boot flow needs one deviation from the stock module: the SpacemiT
# BootROM expects bootloader blobs dd'd to fixed *raw* sector offsets ahead of
# the first partition (sectors 0/1/1280/2048). The `firmwarePartitionOffset`
# option leaves a gap for them, and the `postBuildCommands` hook dd's them in.
# See sd-image-bpi-f3.nix. The table is MBR (not the stock GPT) — see the note
# at the sfdisk invocation for why GPT is unsafe with FSBL at sector 1.
#
# This module creates a bootable SD/eMMC image: a GPT-partitioned image with a
# FAT firmware partition (holding the extlinux.conf + kernel/DTB/initrd) and an
# ext4 root partition. The image is sized to fit its contents and auto-resizes
# the root partition on first boot.
#
# The resulting derivation is placed in config.system.build.sdImage.

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

with lib;

let
  rootfsImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" (
    {
      inherit (config.sdImage) storePaths;
      compressImage = config.sdImage.compressImage;
      populateImageCommands = config.sdImage.populateRootCommands;
      volumeLabel = "NIXOS_SD";
    }
    // optionalAttrs (config.sdImage.rootPartitionUUID != null) {
      uuid = config.sdImage.rootPartitionUUID;
    }
  );
in
{
  imports = [
    (mkRemovedOptionModule [ "sdImage" "bootPartitionID" ]
      "The FAT partition for SD image now only holds the boot firmware files. Use firmwarePartitionID to configure that partition's ID."
    )
    (mkRemovedOptionModule [ "sdImage" "bootSize" ]
      "The boot files for SD image have been moved to the main ext4 partition. The FAT partition now only holds the boot firmware files. Changing its size may not be required."
    )
    "${modulesPath}/profiles/all-hardware.nix"
  ];

  options.sdImage = {
    imageName = mkOption {
      default = "${config.sdImage.imageBaseName}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img";
      description = lib.mdDoc ''
        Name of the generated image file.
      '';
    };

    imageBaseName = mkOption {
      default = "nixos-sd-image";
      description = lib.mdDoc ''
        Prefix of the name of the generated image file.
      '';
    };

    storePaths = mkOption {
      type = with types; listOf package;
      example = literalExpression "[ pkgs.stdenv ]";
      description = lib.mdDoc ''
        Derivations to be included in the Nix store in the generated SD image.
      '';
    };

    firmwarePartitionOffset = mkOption {
      type = types.int;
      default = 8;
      description = lib.mdDoc ''
        Gap in front of the /boot/firmware partition, in mebibytes (1024×1024
        bytes).
        Can be increased to make more space for boards requiring to dd u-boot
        SPL before actual partitions.
      '';
    };

    firmwarePartitionID = mkOption {
      type = types.str;
      default = "0x2178694e";
      description = lib.mdDoc ''
        Volume ID for the /boot/firmware partition on the SD card. This value
        must be a 32-bit hexadecimal number.
      '';
    };

    firmwarePartitionName = mkOption {
      type = types.str;
      default = "FIRMWARE";
      description = lib.mdDoc ''
        Name of the filesystem which holds the boot firmware.
      '';
    };

    rootPartitionUUID = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "14e19a7b-0ae0-484d-9d54-43bd6fdc20c7";
      description = lib.mdDoc ''
        UUID for the filesystem on the main NixOS partition on the SD card.
      '';
    };

    firmwareSize = mkOption {
      type = types.int;
      default = 30;
      description = lib.mdDoc ''
        Size of the /boot/firmware partition, in megabytes.
      '';
    };

    populateFirmwareCommands = mkOption {
      example = literalExpression "'' cp \${pkgs.myBootLoader}/u-boot.bin firmware/ ''";
      description = lib.mdDoc ''
        Shell commands to populate the ./firmware directory.
        All files in that directory are copied to the
        /boot/firmware partition on the SD image.
      '';
    };

    populateRootCommands = mkOption {
      example = literalExpression "''\${config.boot.loader.generic-extlinux-compatible.populateCmd} -c \${config.system.build.toplevel} -d ./files/boot''";
      description = lib.mdDoc ''
        Shell commands to populate the ./files directory.
        All files in that directory are copied to the
        root (/) partition on the SD image. Use this to
        populate the ./files/boot (/boot) directory.
      '';
    };

    postBuildCommands = mkOption {
      example = literalExpression "'' dd if=\${pkgs.myBootLoader}/SPL of=$img bs=1024 seek=1 conv=notrunc ''";
      default = "";
      description = lib.mdDoc ''
        Shell commands to run after the image is built.
        Can be used for boards requiring to dd u-boot SPL before actual partitions.
      '';
    };

    compressImage = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Whether the SD image should be compressed using
        {command}`zstd`.
      '';
    };

    expandOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Whether to configure the sd image to expand it's partition on boot.
      '';
    };
  };

  config = {
    fileSystems = {
      "/boot/firmware" = {
        device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
        fsType = "vfat";
        # Alternatively, this could be removed from the configuration.
        # The filesystem is not needed at runtime, it could be treated
        # as an opaque blob instead of a discrete FAT32 filesystem.
        options = [
          "nofail"
          "noauto"
        ];
      };
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
      };
    };

    sdImage.storePaths = [ config.system.build.toplevel ];

    system.build.sdImage = pkgs.callPackage (
      {
        stdenv,
        dosfstools,
        e2fsprogs,
        mtools,
        libfaketime,
        util-linux,
        zstd,
      }:
      stdenv.mkDerivation {
        name = config.sdImage.imageName;

        nativeBuildInputs = [
          dosfstools
          e2fsprogs
          libfaketime
          mtools
          util-linux
        ]
        ++ lib.optional config.sdImage.compressImage zstd;

        inherit (config.sdImage) imageName compressImage;

        buildCommand = ''
          mkdir -p $out/nix-support $out/sd-image
          export img=$out/sd-image/${config.sdImage.imageName}

          echo "${pkgs.stdenv.buildPlatform.system}" > $out/nix-support/system
          if test -n "$compressImage"; then
            echo "file sd-image $img.zst" >> $out/nix-support/hydra-build-products
          else
            echo "file sd-image $img" >> $out/nix-support/hydra-build-products
          fi

          root_fs=${rootfsImage}
          ${lib.optionalString config.sdImage.compressImage ''
            root_fs=./root-fs.img
            echo "Decompressing rootfs image"
            zstd -d --no-progress "${rootfsImage}" -o $root_fs
          ''}

          # Gap in front of the first partition, in MiB
          gap=${toString config.sdImage.firmwarePartitionOffset}

          # Create the image file sized to fit /boot/firmware and /, plus slack for the gap.
          rootSizeBlocks=$(du -B 512 --apparent-size $root_fs | awk '{ print $1 }')
          firmwareSizeBlocks=$((${toString config.sdImage.firmwareSize} * 1024 * 1024 / 512))
          imageSize=$((rootSizeBlocks * 512 + firmwareSizeBlocks * 512 + gap * 1024 * 1024))
          truncate -s $imageSize $img

          # Use an MBR (msdos) partition table, matching Armbian's SpacemiT family.
          #
          # GPT cannot be used here: the SpacemiT FSBL is dd'd to sector 1, which
          # is exactly where a GPT primary header lives (LBA1) — it would be
          # clobbered. MBR keeps all its metadata in sector 0; the tiny (~80 byte)
          # bootinfo header dd'd at offset 0 coexists with the MBR partition table
          # (which lives at byte offset 446), and sectors 1+ are free for the
          # bootloader blobs. See postBuildCommands in sd-image-bpi-f3.nix.
          #
          # Partition 1 (type c = W95 FAT32 LBA, bootable) is where the vendor
          # U-Boot looks for extlinux.conf + the kernel/DTB/initrd. It starts after
          # the firmwarePartitionOffset gap, which must clear the bootloader blobs.
          sfdisk $img <<EOF
              label: dos
              label-id: ${config.sdImage.firmwarePartitionID}
              unit: sectors

              start=''${gap}M, size=$firmwareSizeBlocks, type=c, bootable
              start=$((gap + ${toString config.sdImage.firmwareSize}))M, type=83
          EOF

          # Copy the rootfs into the SD image
          fsck.ext4 -vn $root_fs
          eval $(partx $img -o START,SECTORS --nr 2 --pairs)
          dd conv=notrunc if=$root_fs of=$img seek=$START count=$SECTORS

          # Create a FAT32 /boot/firmware partition of suitable size into firmware_part.img
          eval $(partx $img -o START,SECTORS --nr 1 --pairs)
          truncate -s $((SECTORS * 512)) firmware_part.img

          mkfs.vfat -i ${config.sdImage.firmwarePartitionID} -n ${config.sdImage.firmwarePartitionName} firmware_part.img

          # Populate the files intended for /boot/firmware
          mkdir firmware
          ${config.sdImage.populateFirmwareCommands}

          find firmware -exec touch --date=2000-01-01 {} +
          # Copy the populated /boot/firmware into the SD image
          cd firmware
          # Force a fixed order in mcopy for better determinism, and avoid file globbing
          for d in $(find . -type d -mindepth 1 | sort); do
            faketime "2000-01-01 00:00:00" mmd -i ../firmware_part.img "::/$d"
          done
          for f in $(find . -type f | sort); do
            mcopy -pvm -i ../firmware_part.img "$f" "::/$f"
          done
          cd ..

          # Verify the FAT partition before copying it.
          fsck.vfat -vn firmware_part.img
          dd conv=notrunc if=firmware_part.img of=$img seek=$START count=$SECTORS

          ${config.sdImage.postBuildCommands}

          if test -n "$compressImage"; then
              zstd -T$NIX_BUILD_CORES --rm $img
          fi
        '';
      }
    ) { };

    boot.postBootCommands = lib.mkIf config.sdImage.expandOnBoot ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x

        # Register the contents of the initial Nix store FIRST. This is the
        # correctness-critical step: until it runs, every shipped store path
        # (the running system AND the NVMe-root toplevel shipped via
        # sdImage.storePaths) is present on disk but *unregistered*, so
        # nixos-rebuild and the NVMe migration's `nix-env --set` fail with
        # "path ... required, but no substituter can build it". It must NOT be
        # gated behind the partition resize below: on this board's marginal SD
        # slot the early-boot resize can fail/stall, and under `set -e` that
        # previously skipped registration entirely — silently breaking the NVMe
        # migration much later with a baffling error. Order it first so a flaky
        # resize can never cost us the registration.
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

        # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

        # Resize the root partition + filesystem to fill the card. Best-effort:
        # a failure here must not undo the registration above (the `if` keeps
        # `set -e` from aborting the block on a resize error).
        rootPart=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=$(lsblk -npo PKNAME $rootPart)
        partNum=$(lsblk -npo MAJ:MIN $rootPart | ${pkgs.gawk}/bin/awk -F: '{print $2}')
        if echo ",+," | sfdisk -N$partNum --no-reread $bootDevice \
          && ${pkgs.parted}/bin/partprobe \
          && ${pkgs.e2fsprogs}/bin/resize2fs $rootPart; then
          echo "root filesystem resized to fill the card."
        else
          echo "warning: root partition resize failed; continuing (store is registered)."
        fi

        # Prevents this from running on later boots.
        rm -f /nix-path-registration
      fi
    '';
  };
}
