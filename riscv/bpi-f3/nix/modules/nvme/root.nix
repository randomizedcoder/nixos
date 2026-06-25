# Root-on-NVMe target for the Banana Pi BPI-F3.
#
# Same system as the SD config, but `/` lives on the NVMe (much faster than the
# SD card — the reason this board is worth using for kernel-dev build loads).
#
# Boot stays on the SD card and is unchanged: the SpacemiT K1 BootROM can only
# pull the first-stage bootloader (FSBL -> OpenSBI -> U-Boot) from raw sectors
# of the SD/eMMC — it has no PCIe driver and cannot read the NVMe. U-Boot then
# loads the kernel + initrd from the SD's FAT firmware partition; the initrd
# brings up PCIe (built into the kernel) + nvme (initrd module, see
# ../kernel.nix) and mounts root by the NIXOS_NVME label.
#
# This config is built into `nixosConfigurations.bpi-f3-nvme` and its toplevel
# is shipped inside the SD image (see ./provision.nix), so `bpi-f3-nvme-install`
# can migrate to the NVMe entirely offline.
#
# We must restate the WHOLE `fileSystems` set, not just `/`: sd-image-bpi-f3.nix
# declares the entire attrset with `lib.mkForce` (priority 50), and NixOS's
# override filtering resolves the `fileSystems` option as a unit — a
# higher-priority definition replaces the lower-priority one wholesale rather
# than merging per-key. `lib.mkOverride 40` here outranks that mkForce, so this
# becomes the sole definition; `/boot/firmware` is repeated verbatim so it is
# preserved. (root.nix is imported only by the NVMe system, so the SD config is
# untouched.)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Build-time shellcheck'd (writeShellApplication) instead of an inline
  # systemd `script`, which NixOS would not lint.
  nvme-swapfile = pkgs.writeShellApplication {
    name = "nvme-swapfile";
    runtimeInputs = [
      pkgs.util-linux # mkswap, swapon, swapoff, fallocate
      pkgs.coreutils # stat, rm, chmod
      pkgs.gawk
    ];
    text = ''
      swapfile=/swapfile
      want_mib=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 }' /proc/meminfo)

      have_mib=0
      if [ -f "$swapfile" ]; then
        have_mib=$(( $(stat -c %s "$swapfile") / 1024 / 1024 ))
      fi

      if [ "$have_mib" -ne "$want_mib" ]; then
        swapoff "$swapfile" 2>/dev/null || true
        rm -f "$swapfile"
        # fallocate (no holes) is what NixOS's own swapfile path uses; ext4
        # accepts the result for swapon.
        fallocate -l "''${want_mib}M" "$swapfile"
        chmod 600 "$swapfile"
        mkswap "$swapfile"
      fi

      swapon --show=NAME --noheadings | grep -qx "$swapfile" || swapon "$swapfile"
    '';
  };
in
{
  fileSystems = lib.mkOverride 40 {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_NVME";
      fsType = "ext4";
    };
    # Auto-mounted here (no `noauto`, unlike the SD image's config): on the
    # NVMe-root system the bootloader installer writes here on every
    # `nixos-rebuild` (see mirroredBoots below), so it must be mounted. `nofail`
    # keeps boot going if the SD is ever absent (root is on the NVMe regardless).
    "/boot/firmware" = {
      device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
      fsType = "vfat";
      options = [ "nofail" ];
    };
  };

  # On-device `nixos-rebuild` must install the kernel/initrd/extlinux.conf onto
  # the SD's FAT firmware partition (what U-Boot actually reads), not the
  # default /boot (a plain dir on the NVMe root that U-Boot never sees). Without
  # this, kernel-dev rebuilds would silently fail to update boot.
  boot.loader.generic-extlinux-compatible.mirroredBoots = [
    { path = "/boot/firmware"; }
  ];

  # NVMe-backed swap — a safety net against OOM-kills during heavy kernel
  # builds (`make -j` / link spikes). Sized to RAM *at runtime* rather than
  # baked into the image: RAM is only known once the board boots (U-Boot's DDR
  # training), and the BPI-F3 ships in 4/8/16 GB variants, so the running NVMe
  # system reads MemTotal and sizes /swapfile to match. A swapfile (not a
  # partition) avoids repartitioning the single NVMe root. Idempotent: it
  # recreates the file only when missing or the wrong size (e.g. moved to a
  # different-capacity board).
  systemd.services.nvme-swapfile = {
    description = "Create and enable an NVMe swapfile sized to RAM";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${nvme-swapfile}/bin/nvme-swapfile";
      ExecStop = "${pkgs.util-linux}/bin/swapoff /swapfile";
    };
  };
}
