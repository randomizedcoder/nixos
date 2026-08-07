# hp/chromebox/chromebox1/configuration.nix
#
# Mirrors hp1's configuration shape (see ~/nixos/hp/hp1/configuration.nix)
# adapted for the smaller Intel Celeron 2955U (Haswell-ULT, 2c/2t,
# 16 GiB RAM, 1.8 TB SATA SSD, 1 GbE onboard). The chromebox joins the
# xdp2 benchmark host fleet as the Intel-CPU data point alongside the
# AMD Zen 1 hp1/hp2/hp3/hp5 boxes.
#
# What this host CAN run (xdp2 docs/physical-testbed.md §9):
#   - Category A — xdp2-rs cargo tests
#   - Category B — flow-dissector matrix userspace ways
#   - Category C — flow-dissector matrix BPF_PROG_TEST_RUN ways
#   - Category D — proto-audit
#   - Category E — perf sweeps over pre-captured pcaps
#   - Category I — unified xdp2-rs vs C matrix
#
# What it CANNOT run (no peer DAC link, no 10/25 GbE NIC):
#   - Category F — XDP samples loaded against real traffic
#   - Category G — AF_XDP throughput
#   - Category H — hardware ntuple offload
#
# CPU isolation: empty list (no isolcpus). The 2-core CPU has no
# headroom to dedicate a core when housekeeping also needs to run; the
# kernel-cmdline tunings (mitigations=off, hugepages, max_cstate=1) are
# still applied via the xdp2.testbed module.

{ config, pkgs, ... }:

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [
      ./disko-chromebox1.nix   # disk layout (preserved from anywhere install)
      ./sysctl.nix
      ./il8n.nix
      ./systemPackages.nix
      ./hosts.nix
      # disableNonEssentialServices = true forces nodeExporter off
      # anyway, but the file is kept on disk so we can flip the toggle
      # if we ever want monitoring on this host.
      #./nodeExporter.nix
      # Kubernetes / docker / k3s stack disabled — see hp1 for the same
      # rationale (benchmark host should have no incidental workloads).
      #./docker-daemon.nix
      #./k3s_master.nix
      #./kubernetes.nix
      #./kubernetes_addonManager.nix
      #./kubernetes_etcd.nix
      #./kubernetes_networking.nix
      #./kubernetes_runtime.nix
      # INSECURE: passwordless root SSH for isolated lab network
      ./sshd-INSECURE.nix
    ];

  # Boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  # Pinned to linuxPackages_latest so chromebox1 matches the hp boxes
  # (xdp2 docs/physical-testbed.md §3). Haswell-ULT is comfortably
  # supported by modern kernels.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # xdp2 physical-testbed tuning. See xdp2 docs/physical-testbed.md §5–§7
  # for the option reference and trade-offs. Two deltas vs the hp1/hp3
  # pattern, both forced by chromebox1's hardware:
  #   - peerInterfaces = [ ] — no peer DAC link.
  #   - isolatedCpus = [ ] — 2 logical CPUs total, no room to dedicate
  #     any to benchmark threads while keeping housekeeping responsive.
  # The kernel-cmdline tunings (mitigations=off, processor.max_cstate=1,
  # transparent_hugepage=never, audit=0, hugepages) still apply.
  xdp2.testbed = {
    enable = true;
    peerInterfaces = [ ];
    addresses = { };
    isolatedCpus = [ ];
    hugepages2M = 256;           # 512 MiB — plenty for parser rings, modest vs 16 GiB total RAM
    disableNonEssentialServices = true;
    lowJitter = false;
    # eno1 default would match the hp boxes; chromebox1's onboard 1 GbE
    # is more likely enp1s0 / enp2s0. Verify post-boot with `ip -br link`
    # and update if it differs — only matters when lowJitter = true
    # (IRQ pinning of the management interface).
    managementInterface = "enp1s0";
    flowDirectorRules = [ ];
    realServicesBench = false;
  };

  # The xdp2 nicTuning module forwards driver = "i40e" by default. With
  # peerInterfaces = [ ] the nic-tuning module compiles away to nothing,
  # so the driver field doesn't matter here — leaving the default.

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
      download-buffer-size = "100000000";
    };
  };

  networking.hostName = "chromebox1";

  services.lldpd.enable = true;

  networking.networkmanager.enable = false;

  # Explicit nameservers — DHCP from the LAN gateway has been observed
  # to land an empty resolv.conf, breaking nix-binary-cache fetches
  # (xdp2 docs/physical-testbed.md §3, hp5 incident 2026-04-20).
  networking.nameservers = [ "172.16.40.1" "1.1.1.1" "8.8.8.8" ];

  time.timeZone = "America/Los_Angeles";

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

  # Define a user account. Password kept from the historical config
  # (lab-only box, password is irrelevant once root SSH key works).
  users.users.das = {
    isNormalUser = true;
    description = "das";
    password = "admin123";
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" "video" ];
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

  # Keep at 25.05 (the existing install's stateVersion); do not bump
  # unless you're prepared to migrate stateful services.
  system.stateVersion = "25.05";
}
