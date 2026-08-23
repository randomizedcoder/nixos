#
# arm/pi-bob/nix/configuration.nix
#
# Top-level machine config. Kept thin: it pulls in the Raspberry Pi 5 hardware
# support and the small per-topic modules in this directory, then sets a few
# core system-wide options.
#

{
  config,
  pkgs,
  lib,
  nixos-raspberrypi,
  ...
}:

{
  imports =
    (with nixos-raspberrypi.nixosModules; [
      # Raspberry Pi 5 hardware support (kernel, firmware, bootloader, dtbs).
      raspberry-pi-5.base
      # Recommended: fixes/optimizations for the 16k memory page size.
      raspberry-pi-5.page-size-16k
    ])
    ++ [
      ./hardware.nix
      ./networking.nix
      ./users.nix
      ./il8n.nix
      # INSECURE demo: password SSH + root login enabled. See the file.
      ./sshd.nix
      ./packages.nix
      ./iperf2.nix
      # node_exporter -> Prometheus -> Grafana web UI (:3000) for host metrics.
      ./monitoring.nix
      # Dedicate a CPU core to the NIC (IRQ/softirq) + iperf2 for clean net perf.
      ./net-tuning.nix
      # zram swap: headroom for on-Pi rebuilds (8 GB is already plenty).
      ./swap.nix
      # Throttle nix-daemon disk I/O so an on-Pi rebuild can't stall the SD card.
      ./io-throttle.nix
      # Seed a writable copy of this config into /home/bob/pi-bob on first boot.
      ./seed-config.nix
    ];

  time.timeZone = "America/Los_Angeles";

  nixpkgs.config.allowUnfree = true;

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

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

  services.timesyncd.enable = true;
  services.fstrim.enable = true;

  # This should match the release the system was first installed from
  # (nixos-raspberrypi/main currently pins nixpkgs 26.05).
  system.stateVersion = "26.05";
}
