#
# arm/pi5-2/configuration.nix
#

{
  config,
  pkgs,
  lib,
  nixos-raspberrypi,
  ...
}:

{
  imports = with nixos-raspberrypi.nixosModules; [
    # Raspberry Pi 5 hardware support (kernel, firmware, bootloader, dtbs)
    raspberry-pi-5.base
    # Recommended: fixes/optimizations for the 16k memory page size
    raspberry-pi-5.page-size-16k

    ./il8n.nix
    # INSECURE: root SSH via key only, on an isolated lab network
    ./sshd-INSECURE.nix
  ];

  # Run from the SD card you flashed (the installer sd-image layout).
  # Labels confirmed against the installer image: NIXOS_SD + FIRMWARE.
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
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
    # 1 TB Kingston NVMe on PCIe — /nix backing store so kernel
    # builds aren't I/O-bound on the SD card. neededForBoot=true
    # makes the mount available in stage-1 before activation reads
    # service units from /nix/store.
    "/nix" = {
      device = "/dev/disk/by-label/NIX_STORE";
      fsType = "ext4";
      options = [ "noatime" ];
      neededForBoot = true;
    };
  };

  # Match the bootloader the installer sd-image already wrote to the card.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Series-3 flow_dissector fast-path kernel (xdp2 kernel-patches/
  # series3-flowdis-fastpath/v1-netdev/). Same Path B overlay as
  # ~/nixos/hp/hp3/test-kernel/ and ~/nixos/laptops/t/test-kernel/,
  # but with linux_rpi5 as the base. Default sysctl
  # net.core.flow_dissector_fastpath=0 so behaviour is unchanged
  # until an operator opts in. Revert to stock by removing this
  # block (kernelPackages falls back to rpi-5.base's mkDefault).
  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.callPackage ./test-kernel { inherit nixos-raspberrypi; }
  );

  networking.hostName = "pi5-2";
  networking.networkmanager.enable = false;

  time.timeZone = "America/Los_Angeles";

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      download-buffer-size = "100000000";
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 10d";
      randomizedDelaySec = "14m";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Define the das user.
  #   - SSH: key only (PasswordAuthentication is off in sshd-INSECURE.nix).
  #   - Console/keyboard: cleartext password below.
  # INSECURE: the password is world-readable in the nix store. Fine only on an
  # isolated lab network. Change the value here to set a different password.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    password = "nixos";
    extraGroups = [
      "wheel"
      "video"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tree
    # perf matched to the running kernel — needed for the xdp2 Phase G
    # cpu-bound matrix orchestrator's `perf stat -p <ksoftirqd PIDs>`
    # call. Without this on PATH the orchestrator returns empty
    # cycles/ins/branches columns for every pi5 cell.
    config.boot.kernelPackages.perf
  ];

  services.lldpd.enable = true;
  services.timesyncd.enable = true;
  services.fstrim.enable = true;

  # mDNS so `pi5-2.local` resolves on the LAN (the installer had this off).
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  # This should match the release the system was first installed from.
  system.stateVersion = "25.11";
}
