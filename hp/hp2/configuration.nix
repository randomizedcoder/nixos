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
      # ./wireless_desktop.nix
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
      # Docker disabled 2026-04-20: hp2 is a dedicated xdp2 benchmark host;
      # docker workloads (gdp container, build cache) were eating /home/das
      # disk and adding scheduler noise (xdp2 docs/physical-testbed.md §7).
      #./docker-daemon.nix
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
      ./nginx.nix
      # INSECURE: passwordless root SSH for isolated lab network
      ./sshd-INSECURE.nix
      # 2026-08-31: hp2 joined the hp1/hp3 RoCEv2 full mesh (design 32).
      ./roce-mtu.nix   # jumbo 9700 on the fabric ports (matches hp1/hp3)
      ./urp.nix        # services.urp: build + load urp.ko (enable-only)
    ];

# https://nixos.wiki/wiki/Kubernetes#reset_to_a_clean_state
# rm -rf /var/lib/kubernetes/ /var/lib/etcd/ /var/lib/cfssl/ /var/lib/kubelet/
# rm -rf /etc/kube-flannel/ /etc/kubernetes/
# rm -rf /var/lib/kubernetes/ /var/lib/etcd/ /var/lib/cfssl/ /var/lib/kubelet/ /etc/kube-flannel/ /etc/kubernetes/

  # Bootloader.
  boot.loader.systemd-boot = {
    enable = true;
    #consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
    memtest86.enable = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  # 2026-08-31: hp2 joined the hp1/hp3 RoCEv2 full mesh (uds-rdma-proxy
  # design 32). Reverted from the custom net-next 7.2-rc1 (netnext-kernel.nix,
  # flow_dissector A/B) back to stock linuxPackages_latest so all three mesh
  # hosts run the SAME kernel (7.2.0) — matches hp1:71 / hp3:76. The old
  # net-next line is kept commented below; restore it if hp2 returns to
  # flow_dissector duty.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # series4 net-next kernel (series4-rfc-tail-v2), for the flow_dissector
  # fast-path perf A/B. See ./netnext-kernel.nix.
  #boot.kernelPackages = pkgs.callPackage ./netnext-kernel.nix {};

  # xdp2 physical-testbed tuning. See xdp2 docs/physical-testbed.md §5–§7
  # for the option reference and trade-offs. lowJitter starts OFF on hp2
  # (the reference host); flip to true once a baseline run exists to
  # compare the delta.
  xdp2.testbed = {
    enable = true;
    peerInterfaces = [ "enp1s0f0np0" "enp1s0f1np1" ];
    addresses = {
      # 2026-08-31 full-mesh re-address (uds-rdma-proxy design 32). Node-pair
      # /29 scheme: third octet = the two node IDs the link joins, host octet
      # = node number. hp2 is node 2. Each of hp2's two ports goes to a
      # DIFFERENT neighbor (mesh), not two cables to one peer.
      #   f0np0 -> hp1 : 10.10.12.0/29  (hp1=.1, hp2=.2)
      #   f1np1 -> hp3 : 10.10.23.0/29  (hp2=.2, hp3=.3)
      # /29 (not /30) per the xdp2 docs/physical-testbed.md Appendix A
      # diagnosis. IPv6 ULA mirrors: fd10:10:<pair>::<node>/64.
      enp1s0f0np0 = {                                            # -> hp1
        local  = "10.10.12.2/29";    peer  = "10.10.12.1";
        local6 = "fd10:10:12::2/64"; peer6 = "fd10:10:12::1";
      };
      enp1s0f1np1 = {                                            # -> hp3
        local  = "10.10.23.2/29";    peer  = "10.10.23.3";
        local6 = "fd10:10:23::2/64"; peer6 = "fd10:10:23::3";
      };
    };
    # 4c/8t Ryzen 5 PRO 2400G → isolate SMT pairs 2,3,4,5,6,7; leave
    # logical CPUs 0,1 for housekeeping (ssh, nix-daemon, kernel).
    isolatedCpus = [ 2 3 4 5 6 7 ];
    hugepages2M = 1024;  # 2 GiB — aligned with hp5; also matches dpdkBenchHost minimum
    disableNonEssentialServices = true;
    lowJitter = false;
    managementInterface = "eno1";

    # 2026-08-31: hp2 is now a Mellanox (ConnectX-4 Lx / mlx5_core) mesh
    # host, not the old Intel X710/i40e reference box. mlx5 steers via
    # tc-flower, so no ntuple Flow Director rules (matches hp1:123 / hp3:111).
    flowDirectorRules = [ ];
    realServicesBench = false;
  };

  # mlx5_core selects the Mellanox NIC tuning branch in xdp2.nicTuning
  # (tc-flower steering, mlx5_comp* IRQ pinning). Overrides the i40e default
  # that physical-testbed.nix forwards. Matches hp3:118 / hp1:130.
  xdp2.nicTuning.driver = "mlx5_core";

  # wrk2 retained on hp2 even though the af-xdp-template bench moved
  # off it (kernel pktgen now drives the peer). Cheap to keep, useful
  # for ad-hoc TCP load generation / regression checks.
  environment.systemPackages = [ pkgs.wrk2 ];
  #boot.kernelPackages = pkgs.linuxPackages;
  #boot.kernelPackages = pkgs.linuxPackages_rpi4

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
  networking.hostName = "hp2";

  services.lldpd.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.networkmanager.enable = false;

  # Explicit nameservers — DHCP from the LAN gateway has been observed
  # to land an empty resolv.conf, breaking nix-binary-cache fetches
  # (xdp2 docs/physical-testbed.md §3, hp5 incident 2026-04-20).
  networking.nameservers = [ "172.16.40.1" "1.1.1.1" "8.8.8.8" ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
    #ANOTHER_VARIABLE = "another-value";
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
  system.stateVersion = "24.05"; # Did you read the comment?

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
