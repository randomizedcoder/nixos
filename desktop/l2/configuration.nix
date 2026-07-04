#
#
# l2/configuration.nix
#

{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

{
  # https://nixos.wiki/wiki/NixOS_modules
  # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
  # l2 is currently configured as a flow-dissector kernel-patch
  # benchmark host (parity with hp5). The WiFi-AP / monitoring /
  # llama.cpp imports below are commented out — un-comment them to
  # restore the prior WiFi-AP + LLM role. See ./test-kernel/ for the
  # series-3 patches and the xdp2.testbed block further down for
  # CPU/IRQ/NIC tuning.
  imports =
    [
      ./disko-l2.nix
      ./hardware-configuration.nix
      # GPU drivers stay imported: kernel-mode-only, no runtime jitter,
      # cheap to leave so the AMD cards probe at boot.
      ./hardware-graphics.nix
      # 2026-06-14: Quadro P620 (Pascal/GP107) driver. Uses legacy_580
      # because R585+ dropped Pascal. See ./hardware-nvidia.nix for
      # why open=false and why no CUDA toolkit is installed by default.
      # Disabled for the net-next 7.2-rc1 kernel: nvidia legacy_580 fails to
      # build against it (gcc-15 + newer kernel: implicit strncpy). l2's
      # compute is AMD ROCm (llama); re-enable when nvidia supports 7.2.
      #./hardware-nvidia.nix
      # 2026-06-16: NVIDIA DCGM Prometheus exporter on :9400 so l's
      # Prometheus can scrape P620 metrics. Tiny systemd service —
      # safe to leave on in benchmark mode (no daemon polling beyond
      # the scrape request itself).
      ./dcgm-exporter.nix
      ./sysctl.nix
      #./wireless_desktop.nix
      ./locale.nix
      ./hosts.nix
      # WiFi-AP NAT/firewall — conntrack adds jitter in benchmarks.
      #./firewall.nix
      #./crowdsec.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported in the flake
      #./home.nix
      # Monitoring stack disabled during kernel testing — scraping is
      # periodic I/O / scheduler noise.
      #./nodeExporter.nix
      #./prometheus.nix
      #./grafana.nix
      #./devnull-monitor.nix
      ./udev-nic-names.nix
      # clickhouse
      #./clickhouse-service.nix
      #./docker-compose.nix
      #./docker-daemon.nix
      #./smokeping.nix
      #./distributed-builds.nix
      #./hyprland.nix
      #./hostapd.nix
      # WiFi AP / Atlantic NIC tuning — both incompatible with the
      # xdp2.testbed-managed benchmark profile.
      #./hostapd-multi.nix
      #./network-optimization.nix
      # BBRv3 congestion control from L4S team
      # Disabled for net-next 7.2-rc1: the L4STeam BBRv3 out-of-tree source
      # doesn't build against it. Re-enable with an updated L4STeam rev.
      #./bbr3-module.nix
      # Multi-queue CAKE (cake_mq) - now included in kernel 7.x
      #./mq-cake-module.nix
      # CPU and IRQ optimization modules — superseded by xdp2.testbed
      # (CPU isolation, IRQ pinning, systemd slices all from the module).
      #./irq-affinity.nix
      #./systemd-slices.nix  # WiFi AP slices, not needed currently
      ./kernel-params.nix
      #./monitoring.nix
      # llama-cpp re-enabled (LLM inference role restored). fan2go left
      # disabled (separate Corsair fan-control concern, not required for
      # inference — amdgpu manages GPU fans by default).
      ./llama-service.nix
      #./fan2go.nix
      # NIC configuration — Mellanox ports are now owned by xdp2.testbed.
      ./network-interfaces.nix
      ./ethtool-nics.nix
      # MQ-CAKE test environment scripts
      #./mq-cake-test.nix
      # WiFi TSF synchronisation via upstream mt76 PTP patches
      #./tsf-sync.nix
      # INSECURE: passwordless root SSH for isolated lab network.
      # Replaces the inline services.openssh block below.
      ./sshd-INSECURE.nix
    ];

  boot = {

    loader.systemd-boot = {
      enable = true;
      consoleMode = "max";
      memtest86.enable = true;
      configurationLimit = 20;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/Linux_kernel
    #kernelPackages = pkgs.linuxPackages;
    #kernelPackages = pkgs.linuxPackages_latest;
    # net-next v7.2-rc1 + the series4 flow_dissector fast-path framework
    # (12 patches, baked into src via the series4-send branch). Built by
    # overriding linux_testing so nixpkgs' config machinery is reused —
    # see ./netnext-kernel.nix. Supersedes the earlier ./test-kernel
    # (stable 7.0.12 + series-3 patches) so we test on the real net-next
    # base the patches target. Revert to `pkgs.callPackage ./test-kernel {}`
    # (wrapped in linuxPackagesFor) or `pkgs.linuxPackages_latest`.
    kernelPackages = pkgs.callPackage ./netnext-kernel.nix {};

    # # Enable mac80211 debugfs for WiFi AQM tuning
    # kernelPatches = [{
    #   name = "mac80211-debugfs";
    #   patch = null;
    #   structuredExtraConfig = with lib.kernel; {
    #     MAC80211_DEBUGFS = yes;
    #     # Also enable general WiFi debugging options
    #     CFG80211_DEBUGFS = yes;
    #   };
    # }];

    initrd.kernelModules = [
      "amdgpu"
    ];

    kernelModules = [
      "bnxt_en"      # Ethernet
      "bnxt_re"      # RoCEv2 RDMA provider
      "ib_uverbs"    # RDMA verbs
      "rdma_ucm"
      "sch_dualpi2"  # DualPI2 L4S AQM packet scheduler (available in kernel 6.17+)
    ];

    # https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
    # https://nixos.org/manual/nixos/stable/options#opt-boot.binfmt.emulatedSystems
    binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];

    # initrd.preDeviceCommands = ''
    #   echo "Loading regulatory database early"
    #   cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db /lib/firmware/
    #   cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db.p7s /lib/firmware/
    # '';

    # cat /proc/cmdline
    # cat /etc/modprobe.d/nixos.conf
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom=US
      options iwlwifi lar_disable=1
      # Allow third-party SFP+ optics (Finisar, etc.) on Intel NICs
      options i40e allow_unsupported_sfp=1
      options ixgbe allow_unsupported_sfp=1
    '';
    #options pcie_aspm=off # power saving thingo

  };

  # https://fzakaria.com/2025/02/26/nix-pragmatism-nix-ld-and-envfs
  # Enable nix-ld for better compatibility with non-Nix binaries
  programs.nix-ld = {
    enable = true;
    # Add commonly needed libraries
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libxml2
      pciutils # for broadcom niccli
      libdrm
      numactl
      rocmPackages.clr.icd
    ];
  };

  # Enable envfs for better compatibility with FHS expectations
  services.envfs = {
    enable = true;
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
      # https://nix.dev/manual/nix/2.28/command-ref/conf-file#conf-max-jobs
      #max-jobs = 12; # default = 1.  Setting this to 1/2 my cores
      http-connections = 100; # default 25
      # https://nix.dev/manual/nix/2.28/command-ref/conf-file#conf-max-substitution-jobs
      max-substitution-jobs = 64; # default 16
      # Build parallelism for 24-core Threadripper PRO 3945WX:
      #
      # Previous: max-jobs=4, cores=6 (4 derivations × 6 cores = 24 total)
      #   Pro: good for parallel multi-package builds
      #   Con: single large builds (kernel, GHC) only used 6 cores (~25% CPU)
      #
      # Current: max-jobs=1, cores=24 (1 derivation × 24 cores)
      #   Pro: large builds use all cores; most nix builds are single-drv anyway
      #   Con: less parallelism when building many independent small packages
      #
      # Changed 2026-03-18: observed kernel --rebuild using only 25% CPU on l2
      # during PR#15508 registerOutputs() benchmarking. Single large builds
      # benefit much more from cores=24 than from parallel small derivations.
      # Can override per-command: nix build --option cores 6 -j4
      max-jobs = 1;
      cores = 24;
    };
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "daily";                   # Schedule the task to run daily
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "l2";

  # Static IP configuration moved to ./network-interfaces.nix

  time.timeZone = "America/Los_Angeles";

  systemd.services.systemd-udev-settle.enable = false;

  # Replaced by ./sshd-INSECURE.nix (imported above).
  # services.openssh = {
  #   enable = true;
  #   settings = {
  #     PasswordAuthentication = false;
  #     KbdInteractiveAuthentication = false;
  #     PermitRootLogin = "yes"; # Change me to "no"!!
  #     #AllowUsers = [ "das" ]
  #   };
  # };

  # programs.ssh.extraConfig = ''
  # Host hp4.home
  #   PubkeyAcceptedKeyTypes ssh-ed25519
  #   ServerAliveInterval 60
  #   IPQoS throughput
  # '';

  # LLDP for cable/port identification
  services.lldpd.enable = true;
  environment.etc."lldpd.conf".text = ''
    # Transmit LLDP on all interfaces (not just those receiving LLDP)
    configure system interface pattern *
    # Also enable CDP for Cisco switches
    configure lldp tx-interval 30
    configure lldp tx-hold 4
  '';
  services.timesyncd.enable = true;
  services.fstrim.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  # environment.variables defined in hardware-graphics.nix
  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
  };

  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  users.users.das = {
    isNormalUser = true;
    description = "das";
    password = "admin123"; # FIX ME!!
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # GPU compute stack re-enabled alongside ./llama-service.nix — the ROCm
  # OpenCL runtime + /opt/rocm/hip symlink are required for the MI50/W5700
  # inference instances. lact (GPU control daemon) and fan2go (Corsair fan
  # control) stay off: neither is required for inference.
  #
  # services.lact.enable = true;                # LACT GPU Control Daemon
  hardware.amdgpu.opencl.enable = true;         # ROCm OpenCL for MI50 (gfx906)
  systemd.tmpfiles.rules = [                    # AMD ROCm /opt/rocm/hip symlink
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];
  # hardware.fan2go.enable = true;              # Corsair Commander PRO fan control

  # xdp2 physical-testbed: CPU isolation, IRQ pinning, NIC tuning,
  # hugepages, lowJitter, disableNonEssentialServices. Mirrors hp5's
  # configuration, adjusted for l2's 12c/24t Threadripper PRO 3945WX
  # and the Mellanox ConnectX-4 Lx ports (lspci 23:00.0 / 23:00.1).
  # See xdp2 docs/physical-testbed.md for the full option reference.
  xdp2.testbed = {
    enable = true;

    peerInterfaces = [ "enp35s0f0np0" "enp35s0f1np1" ];

    # Pair #4: l (generator, .2) <-> l2 (DUT, .5), cabled back-to-back
    # over two ConnectX-4 Lx DAC links. /29 (not /30): xdp2
    # docs/physical-testbed.md §21 — .2 and .5 must share a subnet.
    # 10.10.0/1 = hp2/hp5, 10.10.2/3 = hp1/hp3, so l/l2 take 10.10.4/5.
    # IPv6 ULA: fd10:10:N::M/64, N = v4 third octet, M = v4 host octet.
    addresses = {
      enp35s0f0np0 = {
        local  = "10.10.4.5/29";    peer  = "10.10.4.2";
        local6 = "fd10:10:4::5/64"; peer6 = "fd10:10:4::2";
      };
      enp35s0f1np1 = {
        local  = "10.10.5.5/29";    peer  = "10.10.5.2";
        local6 = "fd10:10:5::5/64"; peer6 = "fd10:10:5::2";
      };
    };

    # 12c/24t Threadripper PRO 3945WX. Isolate logical CPUs 4-23 (10
    # physical cores × 2 SMT threads); housekeeping on 0-3.
    isolatedCpus = [ 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ];

    hugepages2M = 1024;  # 2 GiB — matches hp5/hp2
    disableNonEssentialServices = true;
    lowJitter = true;

    # Management NIC for SSH / nix-daemon — Aquantia Atlantic (enp1s0).
    managementInterface = "enp1s0";

    # Same UDP/443 → queue 1 steering hp5 uses for the
    # af-xdp-template bench. mlx5 ntuple syntax may differ from i40e
    # — if xdp2-nic-tune-enp35s0f0np0.service fails on first boot,
    # drop this list and steer manually via ethtool.
    flowDirectorRules = [
      { interface = "enp35s0f0np0"; flowType = "udp4"; destPort = 443; queue = 1; }
    ];

    realServicesBench = true;
  };

  # The data-plane NICs are Mellanox ConnectX-4 Lx — select the
  # mlx5_core ethtool/IRQ/flow-steering branch in the nic-tuning
  # sub-module. WITHOUT this, xdp2.testbed forwards the default
  # driver = "i40e" (mkDefault in nix/modules/physical-testbed.nix),
  # which is wrong for this card and makes the ethtool-ntuple
  # flowDirectorRules above fail; mlx5_core uses tc-flower instead.
  xdp2.nicTuning.driver = "mlx5_core";

  # # https://nixos.wiki/wiki/Virt-manager
  # virtualisation.libvirtd.enable = true;
  # #programs.virt-manager.enable = true;
  # virtualisation.spiceUSBRedirection.enable = true;

  # virtualisation.containers = {
  #   ociSeccompBpfHook.enable = true;
  # };

  #system.stateVersion = "24.11";
  system.stateVersion = "25.05";

  # systemd.extraConfig = "CPUAffinity=8,20,9,21,10,22,11,23";
  # systemd.user.extraConfig = "CPUAffinity=8,20,9,21,10,22,11,23";

  # systemd.settings.Manager = {
  #   CPUAffinity = "8,20,9,21,10,22,11,23";
  # };
  # systemd.user.settings.Manager = {
  #   CPUAffinity = "8,20,9,21,10,22,11,23";
  # };

  # BBRv3 congestion control from L4S team (out-of-tree module)
  # services.bbr3.enable = true;  # disabled: won't build on net-next 7.2-rc1

  # Multi-queue CAKE (cake_mq) qdisc - backported from net-next/Linux 7.0
  #services.mqCake.enable = true;

  # MQ-CAKE test environment scripts (mq-cake-setup, mq-cake-teardown, mq-cake-verify)
  #services.mq-cake-test.enable = true;

  # Blackmagic DeckLink support
  # lspci | grep -i blackmagic -> DeckLink Mini Recorder
  #hardware.decklink.enable = true;

}

# end
