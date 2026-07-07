# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# sudo nixos-rebuild switch
# sudo nix-channel --update
# nix-shell -p vim
# nmcli device wifi connect MYSSID password PWORD
# systemctl restart display-manager.service

{ config, pkgs, ... }:

# https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
# https://discourse.nixos.org/t/differences-between-nix-channels/13998

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.11.tar.gz home-manager
      # sudo nix-channel --update
      # tutorial
      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
      #<home-manager/nixos>
      #
      ./sysctl.nix
      # ./wireless.nix
      ./hosts.nix
      ./firewall.nix
      ./il8n.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported by the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      # docker-daemon disabled 2026-04-20: hp5 is a dedicated xdp2
      # benchmark host, docker workloads add scheduler noise. Enabled by
      # xdp2.testbed.disableNonEssentialServices = false if truly needed.
      #./docker-daemon.nix
      #./k8s_master.nix
      #./k8s_node.nix
      #./k3s_master.nix
      #./k3s_node.nix
      # Per-NIC X710 tuning is now provided by the xdp2 physical-testbed
      # NixOS module (xdp2.nixosModules.physical-testbed, wired via
      # flake.nix). Old ad-hoc services retained as dead files for the
      # moment — delete after a clean nixos-rebuild switch has validated
      # the module-driven replacement:
      #   ./systemd.services.ethtool-enp1s0f0np0.nix
      #   ./systemd.services.ethtool-enp1s0f1np1.nix
      #./hls_tmpfs.nix
      ./nginx.nix
      #./ffmpeg-hls-service.nix
      # INSECURE: passwordless root SSH for isolated lab network
      ./sshd-INSECURE.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot = {
    enable = true;
    #consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
    memtest86.enable = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  # Pinned to linuxPackages_latest so hp2 + hp5 run the same newest
  # kernel (xdp2 docs/physical-testbed.md §3, 2026-04-20).
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  #
  # TEMPORARY (2026-05-24): switched to a custom net-next 7.1.0-rc4
  # kernel built from the flow-keys-compat-reorder branch's
  # combined-test-rfc tree (4 patches: flow_dissector docs +
  # flow_hash_from_keys_small + sch_cake adoption + bpf_flow PPPoE).
  # See ./test-kernel/default.nix and the xdp2 repo at
  # kernel-patches/test-kernel/ for the build derivation, the
  # rationale, and the post-boot test plan. Restore the line above
  # after testing is complete.
  # series4 net-next kernel (series4-rfc-tail-v2), replacing ./test-kernel
  # for the flow_dissector fast-path perf A/B. See ./netnext-kernel.nix.
  boot.kernelPackages = pkgs.callPackage ./netnext-kernel.nix {};

  # xdp2 physical-testbed tuning. See xdp2 docs/physical-testbed.md §5–§7
  # for the option reference and trade-offs. hp5 enables lowJitter = true
  # because it has the cleaner software baseline (no residual docker/k8s
  # history) and is the target host for ns-precision latency tails.
  xdp2.testbed = {
    enable = true;
    peerInterfaces = [ "enp1s0f0np0" "enp1s0f1np1" ];
    addresses = {
      # /29 (not /30): .2 and .5 must share a subnet; see xdp2
      # docs/physical-testbed.md Appendix A §9 for the diagnosis.
      # IPv6 ULA: fd10:10:N::M/64 where N matches v4 third octet and
      # M matches v4 host octet. See docs/physical-testbed.md §15.
      enp1s0f0np0 = {
        local  = "10.10.0.5/29";    peer  = "10.10.0.2";
        local6 = "fd10:10:0::5/64"; peer6 = "fd10:10:0::2";
      };
      enp1s0f1np1 = {
        local  = "10.10.1.5/29";    peer  = "10.10.1.2";
        local6 = "fd10:10:1::5/64"; peer6 = "fd10:10:1::2";
      };
    };
    # 4c/8t Ryzen 5 PRO 2400G → isolate SMT pairs 2,3,4,5,6,7; leave
    # logical CPUs 0,1 for housekeeping (ssh, nix-daemon, kernel).
    isolatedCpus = [ 2 3 4 5 6 7 ];
    hugepages2M = 1024;  # 2 GiB — aligned with hp2 (where dpdkBenchHost also sets 1024)
    disableNonEssentialServices = true;
    lowJitter = true;
    managementInterface = "eno1";

    # Live X710 ntuple (i40e Flow Director) steering rules — drive the
    # af-xdp-template bench (xdp2 docs/ntuple-template-bench.md).
    # UDP/443 → queue 1 matches what xdp2-flow-dissector-ntuple-template-bench
    # programs and xdp2-bench --mode af-xdp-template binds to. We dropped
    # the prior TCP/22 + TCP/443 entries: SSH falls back to default RSS
    # (still reachable), and the wrk2 TCP/443 path was retired in favour of
    # kernel pktgen sending open-loop UDP. Each rule is programmed
    # idempotently at its list-index slot by xdp2-nic-tune-<ifname>.service.
    flowDirectorRules = [
      { interface = "enp1s0f0np0"; flowType = "udp4"; destPort = 443; queue = 1; }
    ];

    # hp5 is the receiver/listener — re-enable nginx (pinned to CPUs 0,1
    # via CPUAffinity) + install wrk2/h2load. See xdp2 docs/ntuple-template-bench.md
    # for the AF_XDP-zerocopy-steals-the-queue caveat (nginx completes the
    # handshake; wrk's bulk TCP/443 data is steered straight to the parser).
    realServicesBench = true;
  };

  #boot.kernelPackages = pkgs.linuxPackages;
  #boot.kernelPackages = pkgs.linuxPackages_4_19; # 4.19.319
  #boot.kernelPackages = pkgs.linuxPackages_5_4; # 5.4.281
  #boot.kernelPackages = pkgs.linuxPackages_5_15; # 5.15.164
  #boot.kernelPackages = pkgs.linuxPackages_6_1; # 6.1.103
  #boot.kernelPackages = pkgs.linuxPackages_6_8; # 6.8
  #boot.kernelPackages = pkgs.linuxPackages_6_10; # 6.10

  #boot.blacklistedKernelModules = [ "nouveau" ];

  #boot.extraModulePackages = with config.boot.kernelPackages; [
  #  nvidia_x11
  #];

  nix = {
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "weekly";                  # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "100000000";
    };
  };

  # https://nixos.wiki/wiki/Networking
  # https://nlewo.github.io/nixos-manual-sphinx/configuration/ipv4-config.xml.html
  networking.hostName = "hp5";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.networkmanager.enable = false;

  # Explicit nameservers — DHCP from the LAN gateway returned an empty
  # resolv.conf on 2026-04-20, breaking nix-binary-cache fetches and
  # causing a 30-min triage detour (xdp2 docs/physical-testbed.md §3).
  networking.nameservers = [ "172.16.40.1" "1.1.1.1" "8.8.8.8" ];

  time.timeZone = "America/Los_Angeles";


  # hardware.opengl.enable = true;
  # was renamed to:
  # hardware.graphics = {
  #   enable = true;
  #   extraPackages = with pkgs; [
  #     vdpauinfo
  #     libva-utils
  #     nvidia-vaapi-driver
  #     libva-vdpau-driver
  #   ];
  # };

  # hardware.nvidia = {
  #   open = false;
  #   modesetting.enable = true;
  #   powerManagement = {
  #     enable = true;
  #   };
  #   nvidiaSettings = true;
  #   package = pkgs.linuxPackages.nvidia_x11;
  # };

  # services.xserver.videoDrivers = [ "nvidia" ];

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" "video" "nginx" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # services.openssh.enable = true;  # Replaced by sshd-INSECURE.nix


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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

  # virtualisation.libvirtd.enable = true;
  # programs.virt-manager.enable = true;
  # services.qemuGuest.enable = true;

  # Show fastfetch before login prompt
  services.getty.loginProgram = let
    loginWrapper = pkgs.writeShellScript "login-with-fastfetch" ''
      ${pkgs.fastfetch}/bin/fastfetch
      echo ""
      exec ${pkgs.shadow}/bin/login "$@"
    '';
  in "${loginWrapper}";

  # https://wiki.nixos.org/wiki/Laptop
}
