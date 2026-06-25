# NVMe provisioning — shipped only in the SD image (the system that migrates
# the install onto the NVMe). It provides:
#
#   * `bpi-f3-nvme-install` — a guarded one-shot migrator that partitions and
#     formats the NVMe, clones the running system onto it, and repoints the SD's
#     boot config at the NVMe-root system. Re-runnable; wipe-guarded.
#   * a first-boot service that runs the migrator automatically, but ONLY when
#     the NVMe is completely blank (a brand-new device), so we never clobber an
#     NVMe that already holds data. Toggle with `bpi-f3.nvme.autoInstall`.
#   * the NVMe-root system's toplevel, added to the SD image's store paths so
#     the migration needs no network and no on-device compiling.
#
# `nvmeToplevel` is injected via specialArgs from flake.nix (the `bpi-f3-nvme`
# configuration's toplevel). The extlinux populate command is built natively
# here (see `bootPopulate`), not taken from the cross config's populateCmd.
{
  config,
  lib,
  pkgs,
  modulesPath,
  nvmeToplevel,
  ...
}:
let
  # Native (target/riscv64) extlinux-conf-builder for use ON THE DEVICE.
  #
  # NOT `config.boot.loader.generic-extlinux-compatible.populateCmd`: that one
  # is deliberately built against `pkgs.buildPackages` (x86_64) because it's
  # meant to run at image-build time on the build host — invoking it on the
  # board dies with "Exec format error". This rebuilds the same script against
  # `pkgs` (host = riscv64, the cross pkgset's target), i.e. exactly the
  # `builder` NixOS itself uses for on-device activation, and reconstructs the
  # same `-g/-t/-n` args from config.
  bootPopulate =
    let
      blCfg = config.boot.loader;
      cfg = blCfg.generic-extlinux-compatible;
      builder =
        import "${modulesPath}/system/boot/loader/generic-extlinux-compatible/extlinux-conf-builder.nix"
          {
            inherit lib pkgs;
          };
      timeoutStr = if blCfg.timeout == null then "-1" else toString blCfg.timeout;
    in
    "${builder} -g ${toString cfg.configurationLimit} -t ${timeoutStr}"
    + lib.optionalString (
      config.hardware.deviceTree.name != null
    ) " -n ${config.hardware.deviceTree.name}"
    + lib.optionalString (!cfg.useGenerationDeviceTree) " -r";

  bpi-f3-nvme-install = pkgs.writeShellApplication {
    name = "bpi-f3-nvme-install";
    runtimeInputs = [
      pkgs.util-linux # lsblk, findmnt, wipefs, sfdisk, mount, mountpoint, partprobe? (no) — blockdev
      pkgs.e2fsprogs # mkfs.ext4
      pkgs.rsync
      pkgs.coreutils
      config.nix.package # nix-env
    ];
    text = ''
      # Migrate this NixOS install onto the NVMe and make it the boot target.
      # Boot files stay on the SD card's FAT partition (the BootROM cannot read
      # NVMe); only `/` and the Nix store move to the NVMe.

      DEV=/dev/nvme0n1
      PART="''${DEV}p1"
      LABEL=NIXOS_NVME
      BOOT_LABEL=BOOT
      FW_MNT=/boot/firmware
      NVME_TOPLEVEL="${nvmeToplevel}"
      BOOT_POPULATE="${bootPopulate}"

      AUTO=0
      ASSUME_YES=0
      DO_REBOOT=0

      usage() {
        cat <<USAGE
      Usage: bpi-f3-nvme-install [--yes] [--reboot] [--auto]

        --yes      skip the interactive "type YES" confirmation
        --reboot   reboot into the NVMe system once migration completes
        --auto     non-interactive; proceed ONLY if the NVMe is blank, then
                   reboot (used by the first-boot auto-install service)

      Clones the running system to $DEV, then points the SD boot config at it.
      USAGE
      }

      for arg in "$@"; do
        case "$arg" in
          --yes) ASSUME_YES=1 ;;
          --reboot) DO_REBOOT=1 ;;
          --auto) AUTO=1; ASSUME_YES=1; DO_REBOOT=1 ;;
          -h | --help) usage; exit 0 ;;
          *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
        esac
      done

      if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: must run as root (try: sudo bpi-f3-nvme-install)" >&2
        exit 1
      fi

      is_blank() {
        # No partition-table entries and no filesystem/partition-table signatures.
        local parts sigs
        parts=$(lsblk -rno NAME "$1" | tail -n +2 || true)
        sigs=$(wipefs -n "$1" 2>/dev/null | tail -n +2 || true)
        [ -z "$parts" ] && [ -z "$sigs" ]
      }

      # The NVMe enumerates asynchronously over PCIe and the `nvme` module is
      # loaded by udev, so the device node can appear a beat after boot. In
      # --auto (first-boot) mode, wait for it rather than racing the probe (the
      # reason the unit no longer uses ConditionPathExists).
      if [ "$AUTO" = 1 ]; then
        for _ in $(seq 1 60); do
          if [ -b "$DEV" ]; then break; fi
          sleep 0.5
        done
      fi

      if [ ! -b "$DEV" ]; then
        echo "No NVMe device at $DEV — nothing to do."
        [ "$AUTO" = 1 ] && exit 0
        exit 1
      fi

      if [ "$AUTO" = 1 ]; then
        if ! is_blank "$DEV"; then
          echo "$DEV is not blank; leaving it untouched."
          echo "Run 'sudo bpi-f3-nvme-install' to migrate manually."
          exit 0
        fi
        echo "Blank NVMe detected at $DEV."
        echo "Auto-installing NixOS onto it in 10s — press Ctrl-C to cancel."
        # Tolerate the SD transiently wedging during this window (it can fail to
        # even exec `sleep` off the SD store): skip the grace period rather than
        # dying — the migration below retries on its own.
        sleep 10 || true
      fi

      # Never touch a device that is currently mounted (incl. the live root).
      if findmnt -rno SOURCE | grep -q "^$DEV"; then
        echo "ERROR: $DEV (or a partition of it) is mounted; refusing." >&2
        exit 1
      fi

      if [ "$ASSUME_YES" != 1 ]; then
        echo "About to ERASE all data on $DEV:"
        lsblk "$DEV"
        printf 'Type YES to continue: '
        read -r answer
        if [ "$answer" != "YES" ]; then
          echo "Aborted."
          exit 1
        fi
      fi

      # Set up the destination mount + cleanup once, up front, so a retry
      # doesn't leak mounts.
      MNT=$(mktemp -d)
      cleanup() {
        umount "$FW_MNT" 2>/dev/null || true
        umount "$MNT" 2>/dev/null || true
        rmdir "$MNT" 2>/dev/null || true
      }
      trap cleanup EXIT

      # One full migration pass. Every step is checked explicitly and returns
      # non-zero on failure so the retry loop below can re-attempt: the marginal
      # SD slot can transiently wedge under load (an I/O error mid-rsync, or even
      # failing to exec a binary off the SD store) and usually recovers within
      # seconds. Each step is idempotent (wipefs+sfdisk recreate the table, rsync
      # --delete re-syncs only the delta), so re-running from the top is safe.
      migrate() {
        echo "==> Partitioning $DEV (GPT, single Linux partition spanning the disk)"
        wipefs -a "$DEV" || return 1
        # printf|sfdisk rather than a heredoc: avoids the nix-string-indent vs
        # heredoc-terminator trap and reads cleanly inside this function.
        printf 'label: gpt\ntype=linux\n' | sfdisk "$DEV" || return 1

        blockdev --rereadpt "$DEV" || true
        udevadm settle || true
        local found=0
        for _ in $(seq 1 50); do
          if [ -b "$PART" ]; then found=1; break; fi
          sleep 0.2 || true
        done
        if [ "$found" != 1 ]; then
          echo "ERROR: partition $PART never appeared" >&2
          return 1
        fi

        echo "==> Formatting $PART as ext4 (label $LABEL)"
        mkfs.ext4 -F -L "$LABEL" "$PART" || return 1

        if mountpoint -q "$MNT"; then umount "$MNT" 2>/dev/null || true; fi
        mount "$PART" "$MNT" || return 1

        echo "==> Cloning the running system onto the NVMe (rsync)"
        # Whole rootfs incl. the Nix store and all state. Virtual/transient
        # mounts and the SD boot partition are excluded; their mountpoints are
        # recreated. --bwlimit throttles the read so it can't saturate the
        # marginal SD slot controller (sustained full-speed reads wedge it; see
        # sd-overlay.dts).
        rsync -aHAX --numeric-ids --delete --bwlimit=8M \
          --exclude='/proc/*' \
          --exclude='/sys/*' \
          --exclude='/dev/*' \
          --exclude='/run/*' \
          --exclude='/tmp/*' \
          --exclude='/mnt/*' \
          --exclude='/boot/firmware/*' \
          --exclude='/lost+found' \
          --exclude="$MNT" \
          / "$MNT/" || return 1
        for d in proc sys dev run tmp mnt; do
          mkdir -p "$MNT/$d"
        done

        echo "==> Setting the NVMe system profile to the NVMe-root toplevel"
        nix-env --profile "$MNT/nix/var/nix/profiles/system" --set "$NVME_TOPLEVEL" || return 1

        echo "==> Pointing the SD boot config at the NVMe-root system"
        # /boot/firmware is a noauto mount whose mountpoint dir isn't created on
        # the running system (the image build populates that FAT partition
        # out-of-band), so ensure it exists before mounting.
        if ! mountpoint -q "$FW_MNT"; then
          mkdir -p "$FW_MNT"
          mount "/dev/disk/by-label/$BOOT_LABEL" "$FW_MNT" || return 1
        fi
        # BOOT_POPULATE is the populate command *plus* its flags (… -g 20 -t 5
        # -n <dtb>); split it into argv rather than quoting it as one filename.
        local populate_cmd
        read -ra populate_cmd <<< "$BOOT_POPULATE"
        "''${populate_cmd[@]}" -c "$NVME_TOPLEVEL" -d "$FW_MNT" || return 1

        sync
      }

      # Retry the whole migration a few times: the SD slot tends to wedge only
      # transiently during the early-boot I/O burst and recovers within seconds.
      attempt=1
      max_attempts=3
      until migrate; do
        if [ "$attempt" -ge "$max_attempts" ]; then
          echo "ERROR: migration failed after $max_attempts attempts." >&2
          echo "       The SD slot likely wedged hard; power-cycle the board and" >&2
          echo "       it will retry on the next boot (the NVMe is still blank)." >&2
          exit 1
        fi
        echo "Migration attempt $attempt failed (the SD slot may have transiently"
        echo "wedged); waiting for it to settle, then retrying..."
        attempt=$((attempt + 1))
        umount "$MNT" 2>/dev/null || true
        sleep 20 || true
      done
      echo "==> Migration complete. Root will mount from $DEV ($LABEL) on next boot."
      echo "    (Boot files remain on the SD card — keep it inserted.)"

      if [ "$DO_REBOOT" = 1 ]; then
        echo "==> Rebooting into the NVMe system..."
        systemctl reboot
      else
        echo "    Reboot to switch to the NVMe: sudo reboot"
      fi
    '';
  };

  # Erase the NVMe back to blank — handy for re-testing the auto-install from a
  # clean state. Refuses to touch a mounted device, and the confirmation
  # defaults to aborting.
  bpi-f3-nvme-wipe = pkgs.writeShellApplication {
    name = "bpi-f3-nvme-wipe";
    runtimeInputs = [
      pkgs.util-linux # lsblk, findmnt, wipefs, blkdiscard
      pkgs.coreutils # dd
    ];
    text = ''
      # Wipe the NVMe (partition table + filesystem signatures) back to blank.

      DEV=/dev/nvme0n1
      ASSUME_YES=0

      for arg in "$@"; do
        case "$arg" in
          --yes) ASSUME_YES=1 ;;
          -h | --help)
            echo "Usage: bpi-f3-nvme-wipe [--yes]"
            echo "  Erases ALL data on $DEV. Prompts unless --yes is given."
            exit 0
            ;;
          *) echo "unknown argument: $arg" >&2; exit 2 ;;
        esac
      done

      if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: must run as root (try: sudo bpi-f3-nvme-wipe)" >&2
        exit 1
      fi

      if [ ! -b "$DEV" ]; then
        echo "No NVMe device at $DEV — nothing to do."
        exit 1
      fi

      # Never wipe a device that's in use (e.g. if root is already on the NVMe).
      if findmnt -rno SOURCE | grep -q "^$DEV"; then
        echo "ERROR: $DEV (or a partition of it) is mounted; refusing." >&2
        exit 1
      fi

      echo "WARNING: this will PERMANENTLY ERASE all data on $DEV:"
      lsblk "$DEV"
      echo
      echo "Disk model: $(cat "/sys/class/block/$(basename "$DEV")/device/model" 2>/dev/null || echo unknown)"

      if [ "$ASSUME_YES" != 1 ]; then
        printf 'Type YES to erase (anything else aborts): '
        read -r answer
        if [ "$answer" != "YES" ]; then
          echo "Aborted — nothing was changed."
          exit 1
        fi
      fi

      echo "==> Erasing $DEV"
      # Fast path: discard every block (TRIM). Falls back to clearing the
      # partition-table + filesystem signatures if discard isn't supported.
      if ! blkdiscard -f "$DEV" 2>/dev/null; then
        echo "    (blkdiscard unsupported; clearing signatures instead)"
        wipefs -a "$DEV"
        # Zero the first 16 MiB to clear the primary GPT/MBR for good measure.
        dd if=/dev/zero of="$DEV" bs=1M count=16 conv=fsync status=none || true
      fi

      blockdev --rereadpt "$DEV" 2>/dev/null || true
      udevadm settle || true

      echo "==> Done. $DEV is now blank:"
      lsblk "$DEV"
    '';
  };
in
{
  options.bpi-f3.nvme.autoInstall = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      On first boot, automatically migrate the install onto the NVMe when the
      NVMe is completely blank (a brand-new device). An NVMe that already holds
      any partition table or filesystem signature is left untouched. Set to
      false to require running `bpi-f3-nvme-install` by hand.
    '';
  };

  config = {
    environment.systemPackages = [
      bpi-f3-nvme-install
      bpi-f3-nvme-wipe
    ];

    # Tag the SD-root system so its U-Boot/extlinux entry is clearly labelled
    # (e.g. "NixOS - Configuration 1-sd-root-…") instead of a cryptic
    # "Configuration 1". After migration this entry stays in the boot menu as
    # the SD-root system — select it to wipe/re-install the NVMe or to recover
    # if the NVMe system won't boot. (SD-only: the NVMe system isn't tagged.)
    system.nixos.tags = [ "sd-root" ];

    # Ship the NVMe-root system inside the SD image so migration is offline.
    sdImage.storePaths = [ nvmeToplevel ];

    # The hand-added SD-slot controller (../sd-overlay.dts) intermittently
    # raises a spurious SDHCI interrupt the generic driver doesn't ack; under
    # sustained I/O (notably the migration rsync) the kernel sees "irq N:
    # nobody cared" and *disables* the SD IRQ, killing the controller
    # mid-transfer (I/O errors -> aborted ext4 journal). irqpoll makes the
    # kernel poll handlers instead of fatally disabling the line, keeping the
    # SD alive through the migration. Scoped to this SD-boot system only: the
    # migrated NVMe-root system boots without it (the migrator writes the
    # NVMe toplevel's own, irqpoll-free, kernel cmdline).
    boot.kernelParams = [ "irqpoll" ];

    systemd.services = {
      bpi-f3-nvme-autoinstall = lib.mkIf config.bpi-f3.nvme.autoInstall {
        description = "Auto-migrate NixOS onto a blank NVMe (BPI-F3)";
        wantedBy = [ "multi-user.target" ];
        # Order after local-fs.target so the SD rootfs (the rsync source) is
        # mounted. Deliberately NO ConditionPathExists on /dev/nvme0n1: the NVMe
        # enumerates asynchronously over PCIe and may not exist yet when the unit
        # is evaluated (that race got the unit skipped). The script polls for the
        # device instead, and no-ops cleanly if it never appears.
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${bpi-f3-nvme-install}/bin/bpi-f3-nvme-install --auto";
          # Surface progress on the serial console (this box is headless).
          StandardOutput = "journal+console";
          StandardError = "journal+console";
        };
      };

      # Quiet the SD during the first-boot migration. The marginal SD slot wedges
      # under the dense concurrent-I/O burst at multi-user startup; none of these
      # services is needed to migrate (it's entirely local — the NVMe-root
      # toplevel ships in the SD image's store), so order them AFTER the
      # autoinstall to thin out the contention. On a successful migration the
      # service reboots, so they never start on this boot; if it's skipped (NVMe
      # non-blank) the autoinstall exits in ~1s and they start right after; if it
      # fails outright they come up afterwards (ssh/network stay available).
      lldpd.after = lib.mkIf config.bpi-f3.nvme.autoInstall [ "bpi-f3-nvme-autoinstall.service" ];
      dhcpcd.after = lib.mkIf config.bpi-f3.nvme.autoInstall [ "bpi-f3-nvme-autoinstall.service" ];
      sshd.after = lib.mkIf config.bpi-f3.nvme.autoInstall [ "bpi-f3-nvme-autoinstall.service" ];
    };
  };
}
