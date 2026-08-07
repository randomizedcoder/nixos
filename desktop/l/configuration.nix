# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

# sudo nixos-rebuild switch
# sudo nix-channel --update
# nix-shell -p vim
# nmcli device wifi connect MYSSID password PWORD
# systemctl restart display-manager.service

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
  imports =
    [
      ./hardware-configuration.nix
      ./hardware-nvidia.nix
      ./sysctl.nix
      ./wireless_desktop.nix
      ./locale.nix
      ./hosts.nix
      ./firewall.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported in the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      # 2026-06-16: NVIDIA DCGM Prometheus exporter (RTX 3070 metrics).
      # Scrape job is defined in ./prometheus.nix (dcgm_l + dcgm_l2).
      ./dcgm-exporter.nix
      # clickhouse
      ./clickhouse-service.nix
      #./docker-compose.nix
      ./docker-daemon.nix
      #./smokeping.nix
      #./distributed-builds.nix
      #./hyprland.nix
      ./nginx.nix
      # llama-cpp CUDA on RTX 3070
      ./llama-service.nix
      # ollama CUDA on the same RTX 3070, :11434 — tool-calling models for agents
      ./ollama-service.nix
      ./below.nix
      # BBRv3 congestion control from L4S team
      ./bbr3-module.nix
      # Multi-queue CAKE (cake_mq) for scaling CAKE across CPU cores
      # TEMPORARILY DISABLED: patches don't apply cleanly to 6.19.5, needs rebase
      #./mq-cake-module.nix
      # On-demand AnyConnect VPN via OpenConnect
      ./openconnect-vpn.nix
      # On-demand NordLayer VPN via OpenVPN
      ./nordlayer-vpn.nix
      # Direct OpenVPN connection to NordLayer (alternative to the
      # proprietary daemon above — coexists, autoStart=false).
      ./nordlayer-openvpn.nix
      # Lets LAN traffic survive nordlayer's kill-switch (SSH between
      # machines on the local network while the VPN is connected).
      ./nordlayer-lan-bypass.nix
      # Sandboxed nordlayer in a systemd-nspawn container — the
      # recommended entry point for VPN access. The container has its own
      # netns/routing/firewall so nordlayer can't disrupt the host.
      # Reach it via `ssh -J vpn-jump@127.0.0.1:2222 user@remote.vpn`.
      ./nordlayer-sandbox.nix
      # Sandboxed NFB Consulting LADC AnyConnect VPN (OpenConnect) in its own
      # systemd-nspawn container (10.98.0.0/24). Coexists with nordlayer above.
      # Connect with `expect ~/.ssh/nfb-vpn-connect.exp`; then reach NFB devices
      # via `ssh 10.201.10.x` / `ssh <alias>` (ProxyJump nfb-vpn). See
      # ~/Downloads/nfb-ladc-asa01/NFB_VPN_Container_Setup.md.
      ./nfb-vpn-sandbox.nix
      # Series-3 flow_dissector fast-path: SUPERSEDED 2026-06-21. The old
      # 3-patch flowdis-fastpath-module.nix (no per-shape sysctls) is
      # replaced by the v3-namespace 10-patch series via ./test-kernel/,
      # matching hp1/hp2/hp3/hp5/l2 so the Phase H orchestrator can flip
      # net.flow_dissector.<shape> for its A/B. See boot.kernelPackages below.
    ];

  # eBPF flow dissector: attach the basic eth+IP+TCP/UDP fast path as a
  # systemd service (flow-dissector-eth_ip.service). This box runs a lot of
  # plain eth+IP+TCP/UDP, so eth_ip is the right shape. Module comes from the
  # flow-dissector-ebpf flake input; verifies that repo's NixOS module.
  services.flow-dissector-ebpf = {
    enable = true;
    shapes = [ "eth_ip" ];
  };

  boot = {

    loader.systemd-boot = {
      enable = true;
      consoleMode = "max";
      memtest86.enable = true;
      configurationLimit = 20;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/Linux_kernel
    #kernelPackages = pkgs.linuxPackages; # need to run this old kernel to allow nvidia driver to compile :(
    #kernelPackages = pkgs.linuxPackages;
    # Previous (stable LTS, was 6.18.x). Kept for quick revert if the
    # newer kernel + nvidia 610 combination misbehaves.
    #kernelPackages = pkgs.linuxPackages;  # Stable kernel for NVIDIA driver compatibility
    # 2026-06-14: experimenting with newer kernel alongside nvidia 610.x
    # driver (see hardware-nvidia.nix). linuxPackages_latest = 7.0.x at
    # time of switch. Revert by uncommenting the line above and rebuilding.
    # 2026-06-21: v3-namespace 10-patch flow_dissector kernel (see
    # ./test-kernel/default.nix), mirroring hp5/l2. Base is still
    # linuxPackages_latest (7.0.x) so the NVIDIA module rebuilds against
    # the same version. Revert: restore `pkgs.linuxPackages_latest` here.
    kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./test-kernel {});

    #boot.kernelPackages = pkgs.linuxPackages_rpi4

    # kernelPackages = pkgs.linuxPackages // {
    #   kernel = pkgs.linuxPackages.kernel.override {
    #     extraStructuredConfig = with lib.kernel; {
    #       CONFIG_DRM_NOUVEAU = no;
    #     };
    #   };
    # };

    # # https://github.com/tolgaerok/nixos-2405-gnome/blob/main/core/boot/efi/efi.nix#L56C5-L56C21
    # kernelParams = [
    #   "nvidia-drm.modeset=1"
    #   "nvidia-drm.fbdev=1"
    #   # https://www.reddit.com/r/NixOS/comments/u5l3ya/cant_start_x_in_nixos/?rdt=56160
    #   #"nomodeset"
    # ];

    kernelParams = [ "acpi_enforce_resources=lax" ];

    initrd.kernelModules = [
      "amdgpu"
    ];

    kernelModules = [
      "bnxt_en"      # Ethernet
      "bnxt_re"      # RoCEv2 RDMA provider
      "ib_uverbs"    # RDMA verbs
      "rdma_ucm"
      "nvidia"
      "nvidia_uvm"       # Essential for CUDA/llama.cpp
      "nvidia_modeset"
      "nvidia_drm"
    ];

    blacklistedKernelModules = [
      "nouveau"
      #"i915"
    ];

    # https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
    # https://nixos.org/manual/nixos/stable/options#opt-boot.binfmt.emulatedSystems
    binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];

    extraModulePackages = [
      config.boot.kernelPackages.v4l2loopback
    ];

    extraModprobeConfig = ''
      options kvm_intel nested=1
      options v4l2loopback devices=1 video_nr=1 card_label="v4l2loopback" exclusive_caps=1
      # Bluetooth dongle (TP-Link RTL8761BU, 2357:0604) was being powered down by
      # USB autosuspend, killing the MX Vertical mouse until a physical replug
      # (dmesg showed the adapter re-enumerating + reloading rtl8761bu_fw.bin).
      options btusb enable_autosuspend=0
    '';
    # https://github.com/v4l2loopback/v4l2loopback#options
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
      # Add more libraries as needed
      #libpciaccess
    ];
  };

  # Enable envfs for better compatibility with FHS expectations
  services.envfs = {
    enable = true;
  };

  # For OBS
  security.polkit.enable = true;

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
      trusted-users = [ "das" ];
      # https://nix.dev/manual/nix/2.28/command-ref/conf-file#conf-max-jobs
      #max-jobs = 12; # default = 1.  Setting this to 1/2 my cores
      http-connections = 100; # default 25
      # https://nix.dev/manual/nix/2.28/command-ref/conf-file#conf-max-substitution-jobs
      max-substitution-jobs = 64; # default 16
      # Build parallelism for 24-thread Threadripper PRO 3945WX:
      #
      # Previous: max-jobs=4, cores=6 (4 derivations × 6 cores = 24 total)
      #   Pro: good for parallel multi-package builds
      #   Con: single large builds (kernel, GHC) only used 6 cores (~25% CPU)
      #
      # Current: max-jobs=1, cores=24 (1 derivation × 24 cores)
      #   Pro: large builds use all cores; most nix builds are single-drv anyway
      #   Con: less parallelism when building many independent small packages
      #
      # Can override per-command: nix build --option cores 6 -j4
      max-jobs = 1;
      cores = 24;
      extra-sandbox-paths = [ "/var/cache/bazel-nix" ];
    };
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "daily";                   # Schedule the task to run daily
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "l";

  time.timeZone = "America/Los_Angeles";

  # Bluetooth (TP-Link RTL8761BU dongle -> Logitech MX Vertical mouse). Was
  # previously running on implicit GNOME/BlueZ defaults; make it explicit.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      # Faster/robust reconnection for HID peripherals (mouse).
      FastConnectable = true;
    };
  };

  services.udev.packages = [ pkgs.gnome-settings-daemon ];
  # services.udev.packages = [ pkgs.gnome.gnome-settings-daemon ];

  # EspoTek Labrador USB oscilloscope
  services.udev.extraRules = ''
    # EspoTek Labrador - main device
    ENV{ID_VENDOR_ID}=="03eb", ENV{ID_MODEL_ID}=="ba94", SYMLINK="EspoTek_Labrador", MODE="0666"
    ENV{ID_VENDOR_ID}=="03eb", ENV{ID_MODEL_ID}=="a000", SYMLINK="EspoTek_Labrador", MODE="0666"
    # EspoTek Labrador - DFU bootloader
    ENV{ID_VENDOR_ID}=="03eb", ENV{ID_MODEL_ID}=="2fe4", SYMLINK="ATXMEGA32A4U_DFU_Bootloader", MODE="0666"
  '';

  # # https://nixos.wiki/wiki/NixOS_Wiki:Audio
  # services.pulseaudio.enable = false; # Use Pipewire, the modern sound subsystem

  security.rtkit.enable = true; # Enable RealtimeKit for audio purposes

  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  # Enable PipeWire screen capture
  environment.sessionVariables = {
    TERM = "xterm-256color";
    # PipeWire screen capture
    PIPEWIRE_SCREEN_CAPTURE = "1";
    # Force Flameshot to use Wayland
    QT_QPA_PLATFORM = "wayland";
    #MY_VARIABLE = "my-value";
  };
  # fix for /bin/sh for the claude bug
  environment.binsh = "${pkgs.bash}/bin/bash";

  # System-wide LD_LIBRARY_PATH for ROCm tools (rocm-smi needs libdrm_amdgpu.so)
  # Use lib.mkForce to override pipewire's setting, combining both paths
  environment.variables = {
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.libdrm}/lib:${pkgs.pipewire.jack}/lib";
  };

  # Allow sudo to preserve LD_LIBRARY_PATH for ROCm tools
  security.sudo.extraConfig = ''
    Defaults env_keep += "LD_LIBRARY_PATH"
  '';

  services.openssh.enable = true;
  # Allow root self-login by key (PermitRootLogin defaults to
  # "prohibit-password", i.e. key-only). Needed so the series-3
  # flow_dissector test orchestrators can drive l as the generator via
  # `ssh root@l` — same mechanism/key as l2 and the hp fleet. Password
  # auth is intentionally left at its default here (NOT disabled) since
  # l is the daily-driver desktop.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
  ];
  # programs.ssh.extraConfig = ''
  # Host hp4.home
  #   PubkeyAcceptedKeyTypes ssh-ed25519
  #   ServerAliveInterval 60
  #   #IPQoS throughput

  # # Optimizations for nfbQotom SSH sessions
  # # Reduce GPU rendering load in terminals with these settings
  # Host nfbQotom 172.16.40.184 172.16.40.185
  #   ControlMaster auto
  #   ControlPath ~/.ssh/master-%r@%h:%p
  #   ControlPersist 10m
  #   ServerAliveInterval 30
  #   ServerAliveCountMax 3
  #   Compression no
  # '';

  services.lldpd.enable = true;
  services.timesyncd.enable = true;
  services.fstrim.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  #services.bpftune.enable = true;
  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # https://nixos.wiki/wiki/Printing
  # HP MFP M477fdw printer support
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip pkgs.hplipWithPlugin pkgs.gutenprint pkgs.gutenprintBin ];
    browsing = true;
    defaultShared = false;
  };

  # Declarative printer configuration (using IPP Everywhere / driverless)
  hardware.printers = {
    ensurePrinters = [
      {
        name = "HP_M477fdw";
        description = "HP Color LaserJet MFP M477fdw";
        location = "Home Office";
        deviceUri = "ipp://172.16.50.63:631/ipp/print";
        model = "everywhere";
        ppdOptions = {
          PageSize = "Letter";
        };
      }
    ];
    ensureDefaultPrinter = "HP_M477fdw";
  };

  # Enable CUPS browsed for automatic printer discovery
  services.avahi.publish.enable = true;
  services.avahi.publish.userServices = true;

  # Scanner support for HP MFP (multifunction printer)
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplip ];
  };

  # flameshot now in home.nix
  # https://wiki.nixos.org/wiki/Flameshot
  # services.flameshot = {
  #   enable = true;
  #   settings.General = {
  #     showStartupLaunchMessage = false;
  #     saveLastRegion = true;
  #   };
  # };

  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  # ClickHouse enabled in clickhouse-service.nix

  # environment.variables defined in hardware-graphics.nix
  # environment.sessionVariables = {
  #   TERM = "xterm-256color";
  #   #MY_VARIABLE = "my-value";
  # };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" "pipewire" "dialout" "scanner" "lp" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  # package moved to systemPackages.nix
  # environment.systemPackages = with pkgs; [

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/hardware/amdgpu.nix
  hardware.amdgpu.opencl.enable = true;

  # hardware.graphics = {
  #   enable = true; # auto includes mesa
  #   package = pkgs.mesa;
  #   extraPackages = with pkgs; [
  #     libglvnd
  #     #libva-vdpau-driver
  #     #libvdpau-va-gl
  #     rocmPackages.clr.icd
  #     amdvlk
  #   ];
  # };

  services.xserver = {
    enable = true;
    videoDrivers = [ "amdgpu" "nvidia" ];
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;

  # https://nixos.wiki/wiki/AMD_GPU
  systemd.tmpfiles.rules = [
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # Enable LACT GPU Control Daemon
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/hardware/lact.nix
  services.lact = {
    enable = true;
  };

  # Enable hardware graphics for CUDA runtime
  hardware.graphics.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
    ];
    config.common.default = "gnome";
    config.gnome.default = "gnome";
  };

  services.dbus.packages = with pkgs; [
    xdg-desktop-portal
    xdg-desktop-portal-gtk
  ];

  # # https://wiki.hyprland.org/Nix/Hyprland-on-NixOS/
  # programs.hyprland = {
  #   enable = true;
  #   xwayland.enable = true;
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # # https://nixos.wiki/wiki/Podman
  # virtualisation.podman = {
  #   enable = true;
  #   dockerCompat = true;
  #   defaultNetwork.settings.dns_enabled = true;
  #   autoPrune.enable = true;
  # };
  # #virtualisation.oci-containers.backend = "podman";
  # # virtualisation.oci-containers.containers = {
  # #   container-name = {
  # #     image = "container-image";
  # #     autoStart = true;
  # #     ports = [ "127.0.0.1:1234:1234" ];
  # #   };
  # # };

  # https://nixos.wiki/wiki/Virt-manager
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  virtualisation.containers = {
    ociSeccompBpfHook.enable = true;
  };

  # guest
  # services.qemuGuest.enable = true;
  # services.spice-vdagentd.enable = true;

  # https://wiki.nixos.org/wiki/Laptop

  # Performance Co-Pilot monitoring - this was a test of the pcp package
  #services.pcp.enable = true;

  # BBRv3 congestion control from L4S team (out-of-tree module)
  services.bbr3.enable = true;

  # Multi-queue CAKE (cake_mq) - scales CAKE across CPU cores (kernel patches)
  # TEMPORARILY DISABLED: patches don't apply cleanly to 6.19.5, needs rebase
  #services.mqCake.enable = true;

  # Second NVMe drive (2TB data storage)
  fileSystems."/mnt" = {
    device = "/dev/disk/by-uuid/d249da43-6743-4397-a50c-e1047a08e005";
    fsType = "ext4";
  };

  # Bind mount Downloads from second NVMe to home directory
  fileSystems."/home/das/Downloads" = {
    device = "/mnt/Downloads";
    fsType = "none";
    options = [ "bind" ];
  };

  # ===================================================================
  # Series-3 perf-testing: l is the generator for the 25 GbE l <-> l2
  # pair (Pair #4, see xdp2 docs/physical-testbed.md §21).
  # ===================================================================

  # Series-3 flow_dissector fast-path is now applied via the v3-namespace
  # 10-patch ./test-kernel/ overlay (see boot.kernelPackages above), which
  # ships per-shape sysctls under net.flow_dissector.*. The old
  # services.flowdis-fastpath.enable path is retired (2026-06-21).

  # xdp2 physical-testbed in GENERATOR-LITE mode. Unlike the dedicated
  # hp/l2 hosts, l is a daily-driver desktop: keep mitigations on, keep
  # all desktop services, skip the always-on C-state/THP/audit tuning,
  # and isolate only ~4 logical cores for traffic generation. The
  # physical-testbed module is imported in flake.nix.
  xdp2.testbed = {
    enable = true;

    peerInterfaces = [ "enp35s0f0np0" "enp35s0f1np1" ];

    # Pair #4: l (generator, .2) <-> l2 (DUT, .5). /29 subnets; IPv6 ULA
    # fd10:10:N::M/64 (N = v4 third octet, M = v4 host octet).
    addresses = {
      enp35s0f0np0 = {
        local  = "10.10.4.2/29";    peer  = "10.10.4.5";
        local6 = "fd10:10:4::2/64"; peer6 = "fd10:10:4::5";
      };
      enp35s0f1np1 = {
        local  = "10.10.5.2/29";    peer  = "10.10.5.5";
        local6 = "fd10:10:5::2/64"; peer6 = "fd10:10:5::5";
      };
    };

    # Only ~4 logical cores isolated for the generator; the remaining
    # ~20 threads stay for the interactive desktop. The soak harness
    # taskset-pins iperf/tcpreplay onto these (GEN_CORES=2-5).
    isolatedCpus = [ 2 3 4 5 ];
    hugepages2M = 512;

    # --- generator-lite: keep the desktop healthy and secure ---
    dedicatedHost = false;               # skip max_cstate=1 / THP=never / audit=0
    disableMitigations = false;          # CPU mitigations stay ON (daily driver)
    disableNonEssentialServices = false; # keep GNOME / printing / VPN / etc.
    lowJitter = false;                   # keep turbo for interactive use

    # Management interface (kept for SSH / nix); enp1s0 is l's onboard NIC.
    managementInterface = "enp1s0";
  };

  # Mellanox ports use the same mlx5_core ethtool/IRQ/tc-flower branch
  # as l2 and hp1/hp3 (NOT the default i40e).
  xdp2.nicTuning.driver = "mlx5_core";

  # l runs NetworkManager (wireless_desktop.nix). Hand the data-plane
  # Mellanox ports to xdp2.testbed's static config instead of letting NM
  # manage / DHCP them.
  networking.networkmanager.unmanaged = [
    "interface-name:enp35s0f0np0"
    "interface-name:enp35s0f1np1"
  ];

  system.stateVersion = "24.11";

}

# end
