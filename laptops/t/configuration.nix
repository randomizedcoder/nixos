# laptops/t/configuration.nix
#
# Mirrors hp1's configuration shape (see ~/nixos/hp/hp1/configuration.nix)
# adapted for an Intel Comet Lake-H laptop. t is the high-end Intel
# data point in the xdp2 benchmark fleet:
#
#   | Host        | uarch         | cores  | clock         | role        |
#   | ----------- | ------------- | ------ | ------------- | ----------- |
#   | hp1..hp5    | Zen 1 (Ryzen) | 4c/8t  | 3.4 GHz       | x710/mlx5   |
#   | chromebox1  | Haswell-ULT   | 2c/2t  | 1.4 GHz       | no NIC      |
#   | t (this)    | Comet Lake-H  | 8c/16t | 2.4–5.3 GHz   | WiFi only   |
#
# What this host CAN run (xdp2 docs/physical-testbed.md §9):
#   - Category A — xdp2-rs cargo tests
#   - Category B — flow-dissector matrix userspace ways
#   - Category C — flow-dissector matrix BPF_PROG_TEST_RUN ways
#   - Category D — proto-audit
#   - Category E — perf sweeps over pre-captured pcaps
#   - Category I — unified xdp2-rs vs C matrix
#
# What it CANNOT run (no wired ethernet, no peer link):
#   - Category F — XDP samples loaded against real traffic
#   - Category G — AF_XDP throughput
#   - Category H — hardware ntuple offload
#
# Full strip from the prior laptop config: dropped Hyprland (Wayland
# compositor), NVIDIA proprietary driver, OBS / v4l2loopback,
# libvirtd / virt-manager / spice, docker, binfmt emulation for
# aarch64/riscv64, printing, pipewire/pulse, hardware graphics for
# video accel, bpftune, GNOME settings daemon, polkit (was only for
# OBS), distributed-builds, x server. Reverting to laptop usability
# means restoring those files in `imports` and the relevant blocks
# below.

{ config, pkgs, ... }:

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./sysctl.nix
      ./locale.nix
      ./hosts.nix
      ./firewall.nix
      ./systemPackages.nix
      # home manager is imported by the flake
      #./home.nix
      # INSECURE: passwordless root SSH for isolated lab network
      ./sshd-INSECURE.nix
      # ---- disabled for benchmark mode (uncomment to restore desktop) ----
      #./hardware-graphics.nix       # NVIDIA + Intel graphics for video accel
      #./wireless_desktop.nix        # NetworkManager wifi (now inlined below)
      #./docker-daemon.nix           # benchmark host has no incidental workloads
      #./distributed-builds.nix      # don't drive remote builders from a bench
      #./nodeExporter.nix            # forced off by disableNonEssentialServices
      #./prometheus.nix              # ditto
      #./grafana.nix                 # ditto
    ];

  # Boot loader.
  boot.loader.systemd-boot = {
    enable = true;
    consoleMode = "max";
    memtest86.enable = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  # linuxPackages_latest + the 3 series-3 flow_dissector fast-path
  # patches as a kernelPatches overlay. See ./test-kernel/default.nix
  # for the patch list + rationale. To revert to stock, swap the
  # block below back to `boot.kernelPackages = pkgs.linuxPackages_latest;`
  # (xdp2 docs/physical-testbed.md §3, §16; series 3:
  # xdp2 kernel-patches/series3-flowdis-fastpath/v1-netdev/).
  boot.kernelPackages =
    let customKernel = pkgs.callPackage ./test-kernel { };
    in pkgs.linuxPackagesFor customKernel;

  # Blacklist nouveau just in case — the NVIDIA Quadro T2000 is still
  # physically present and nouveau likes to grab it. Without nouveau the
  # GPU stays uninitialised which is what we want on a headless bench
  # host.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # xdp2 physical-testbed tuning. See xdp2 docs/physical-testbed.md §5–§7
  # for the option reference and trade-offs. t mirrors the hp1 pattern
  # for CPU isolation (keep CPUs 0,1 for housekeeping, isolate the
  # rest), with two adaptations for the laptop hardware:
  #   - peerInterfaces = [ ]  (no wired ethernet; WiFi-only)
  #   - managementInterface = "wlp0s20f3"  (the Intel CNVi WiFi)
  xdp2.testbed = {
    enable = true;
    peerInterfaces = [ ];
    addresses = { };
    # Intel SMT layout: CPU N and N+8 are siblings on phys core N
    # (verified via `lscpu --extended`). Keeping CPUs 0,1 leaves one
    # thread of phys cores 0 and 1 free for housekeeping; their SMT
    # siblings (CPUs 8,9) get isolated which is fine — nothing
    # schedules onto isolated CPUs unless explicitly bound, and the
    # benchmark threads on the isolated cores benefit from the SMT
    # sibling being idle.
    isolatedCpus = [ 2 3 4 5 6 7 8 9 10 11 12 13 14 15 ];
    hugepages2M = 1024;          # 2 GiB — aligned with hp1/hp3/hp5
    disableNonEssentialServices = true;
    lowJitter = false;
    managementInterface = "wlp0s20f3";  # Intel CNVi WiFi, the only network path
    flowDirectorRules = [ ];
    realServicesBench = false;
  };

  # The xdp2.nicTuning module defaults to driver = "i40e". With
  # peerInterfaces = [ ] the nic-tuning module compiles away to
  # nothing, so the driver field is irrelevant — leaving the default.

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 10d";
      randomizedDelaySec = "14m";
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
    };
  };

  networking.hostName = "t";

  # WiFi is the only network path to this host. NetworkManager retains
  # the saved SSID/credentials in /etc/NetworkManager/system-connections/
  # across rebuilds, so this only re-enables the daemon — it doesn't
  # reconfigure anything.
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false;
  };

  # Explicit nameservers — DHCP from the LAN gateway has been observed
  # to land an empty resolv.conf, breaking nix-binary-cache fetches
  # (xdp2 docs/physical-testbed.md §3, hp5 incident 2026-04-20).
  networking.nameservers = [ "172.16.40.1" "1.1.1.1" "8.8.8.8" ];

  services.lldpd.enable = true;

  time.timeZone = "America/Los_Angeles";

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    # extraGroups trimmed: dropped "kvm" "libvirtd" "docker" since
    # those services are off in benchmark mode. Kept "networkmanager"
    # so das can re-join WiFi from the console without sudo, and
    # "video" + "wheel" for general admin.
    extraGroups = [ "wheel" "networkmanager" "video" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # services.openssh.enable = true;  # Replaced by sshd-INSECURE.nix

  services.timesyncd.enable = true;
  services.fstrim.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  # Disable ModemManager (laptop hardware leftover; no modem to manage).
  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  # Keep stateVersion at the install version (24.11). Bumping changes
  # the default behavior of stateful services; don't touch unless
  # you've reviewed the migration notes.
  system.stateVersion = "24.11";
}
