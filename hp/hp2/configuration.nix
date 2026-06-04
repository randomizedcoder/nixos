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
  # Pinned to linuxPackages_latest so hp2 + hp5 run the same newest
  # kernel (xdp2 docs/physical-testbed.md §3 — was channel-default
  # 6.12.x on stable while hp5 ran 6.18.x on unstable, 2026-04-20).
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  #
  # TEMPORARY (2026-05-24): switched to a custom net-next 7.1.0-rc4
  # kernel built from the flow-keys-compat-reorder branch's
  # combined-test-rfc tree (4 patches: flow_dissector docs +
  # flow_hash_from_keys_small + sch_cake adoption + bpf_flow PPPoE).
  # Mirrors the same swap on hp5. See ./test-kernel/default.nix and
  # the xdp2 repo at kernel-patches/test-kernel/ for the build
  # derivation, rationale, and post-boot test plan. Restore the line
  # above after testing is complete.
  boot.kernelPackages = pkgs.linuxPackagesFor
    (pkgs.callPackage ./test-kernel {});

  # xdp2 physical-testbed tuning. See xdp2 docs/physical-testbed.md §5–§7
  # for the option reference and trade-offs. lowJitter starts OFF on hp2
  # (the reference host); flip to true once a baseline run exists to
  # compare the delta.
  xdp2.testbed = {
    enable = true;
    peerInterfaces = [ "enp1s0f0np0" "enp1s0f1np1" ];
    addresses = {
      # /29 (not /30): .2 and .5 must share a subnet; see xdp2
      # docs/physical-testbed.md Appendix A §9 for the diagnosis.
      # IPv6 ULA: fd10:10:N::M/64 where N matches v4 third octet and
      # M matches v4 host octet. See docs/physical-testbed.md §15.
      enp1s0f0np0 = {
        local  = "10.10.0.2/29";    peer  = "10.10.0.5";
        local6 = "fd10:10:0::2/64"; peer6 = "fd10:10:0::5";
      };
      enp1s0f1np1 = {
        local  = "10.10.1.2/29";    peer  = "10.10.1.5";
        local6 = "fd10:10:1::2/64"; peer6 = "fd10:10:1::5";
      };
    };
    # 4c/8t Ryzen 5 PRO 2400G → isolate SMT pairs 2,3,4,5,6,7; leave
    # logical CPUs 0,1 for housekeeping (ssh, nix-daemon, kernel).
    isolatedCpus = [ 2 3 4 5 6 7 ];
    hugepages2M = 1024;  # 2 GiB — aligned with hp5; also matches dpdkBenchHost minimum
    disableNonEssentialServices = true;
    lowJitter = false;
    managementInterface = "eno1";

    # Live X710 ntuple (i40e Flow Director) steering rules, matched with
    # hp5. hp2 is the peer/sender but we program the same UDP/443 → q1
    # rule here so role-swap runs (where hp2 is the receiver) steer
    # consistently. See xdp2 docs/ntuple-template-bench.md.
    flowDirectorRules = [
      { interface = "enp1s0f0np0"; flowType = "udp4"; destPort = 443; queue = 1; }
    ];
    # realServicesBench intentionally OFF on hp2: hp5 hosts the nginx
    # target; hp2 runs the kernel pktgen driver (no wrk2/nginx needed).

    # Deliverable-2 DPDK alternative for the hp2 kernel pktgen ~1.37 Mpps
    # TX cap. Reserves vfio-pci + 1024×2 MiB hugepages + iommu=pt at boot
    # so `nix run .#xdp2-exp-dpdk-baseline -- hp5 hp2` can rebind
    # enp1s0f0np0 to vfio-pci and run DPDK pktgen userspace. The driver
    # rebind happens INSIDE the orchestrator's lifecycle (trap-driven
    # cleanup restores i40e on exit); this option only ensures the
    # kernel-cmdline / module bits are present. Intentionally NOT set on
    # hp5 — hp5's NIC must stay on i40e so Flow Director rules survive.
    #
    # TEMPORARY (2026-05-24): commented out — the xdp2 flake input locked
    # at f36b3237c1abb (2026-04-26) doesn't yet declare this option, which
    # blocks `nixos-rebuild` eval. Restore once the xdp2 input is bumped
    # to a commit that adds the dpdkBenchHost option.
    #dpdkBenchHost = true;
  };

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
