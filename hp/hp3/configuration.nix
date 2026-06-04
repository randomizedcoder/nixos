# hp/hp3/configuration.nix
#
# Mirrors hp5's configuration (see ~/nixos/hp/hp5/configuration.nix) so
# that hp1 + hp3 form a second xdp2 benchmark testbed pair. Only deltas
# vs hp5 are:
#   - hostname is "hp3" (not "hp5")
#   - xdp2.testbed.addresses sit on 10.10.2.0/29 + 10.10.3.0/29 (the
#     dedicated subnet pair for the hp1↔hp3 link) rather than .0/.1
#   - xdp2.nicTuning.driver = "mlx5_core" (Mellanox 25 GbE DAC)
#     instead of i40e (Intel X710 10 GbE fibre)
#   - hp3 takes the "dut" role on this pair (mirrors hp5 on the i40e
#     pair); hp1 is the generator
#
# See xdp2 docs/physical-testbed.md §14 for the second-pair overview.

{ config, pkgs, ... }:

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./sysctl.nix
      # ./wireless.nix              # headless benchmark host
      ./hosts.nix
      ./firewall.nix
      ./il8n.nix
      ./systemPackages.nix
      # home manager is imported by the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      # Disabled for xdp2 benchmark host — see hp5 for the same rationale
      # (docker daemon + k8s/k3s add scheduler noise and disk pressure).
      #./docker-daemon.nix
      #./k3s_master.nix
      #./k8s_master.nix
      # INSECURE: passwordless root SSH for isolated lab network
      ./sshd-INSECURE.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot = {
    enable = true;
    memtest86.enable = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  # Pinned to linuxPackages_latest so hp1 + hp2 + hp3 + hp5 all run the
  # same newest kernel (xdp2 docs/physical-testbed.md §3).
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  #
  # TEMPORARY (2026-05-24): switched to a custom net-next 7.1.0-rc4
  # kernel built from the flow-keys-compat-reorder branch's
  # combined-test-rfc tree (4 patches: flow_dissector docs +
  # flow_hash_from_keys_small + sch_cake adoption + bpf_flow PPPoE).
  # Mirrors the same swap on hp2/hp5. See ./test-kernel/default.nix
  # and the xdp2 repo at kernel-patches/test-kernel/ for the build
  # derivation, rationale, and post-boot test plan. Restore the line
  # above after testing is complete.
  boot.kernelPackages = pkgs.linuxPackagesFor
    (pkgs.callPackage ./test-kernel {});

  # xdp2 physical-testbed tuning. See xdp2 docs/physical-testbed.md §5–§7
  # for the option reference and trade-offs. hp3 mirrors hp5's "dut"
  # role on the new mlx5 pair: peer = hp1, addresses .3 on each link.
  xdp2.testbed = {
    enable = true;
    peerInterfaces = [ "enp1s0f0np0" "enp1s0f1np1" ];
    addresses = {
      # /29 (not /30): .1 and .3 must share a subnet; see xdp2
      # docs/physical-testbed.md Appendix A §10 for the diagnosis.
      # IPv6 ULA: fd10:10:N::M/64 where N matches v4 third octet and
      # M matches v4 host octet. See docs/physical-testbed.md §15.
      enp1s0f0np0 = {
        local  = "10.10.2.3/29";    peer  = "10.10.2.1";
        local6 = "fd10:10:2::3/64"; peer6 = "fd10:10:2::1";
      };
      enp1s0f1np1 = {
        local  = "10.10.3.3/29";    peer  = "10.10.3.1";
        local6 = "fd10:10:3::3/64"; peer6 = "fd10:10:3::1";
      };
    };
    # 4c/8t Ryzen 5 PRO (assumed; verify with `lscpu` post-boot) →
    # isolate SMT pairs 2..7; leave logical CPUs 0,1 for housekeeping
    # (ssh, nix-daemon, kernel).
    isolatedCpus = [ 2 3 4 5 6 7 ];
    hugepages2M = 1024;  # 2 GiB — aligned with hp2/hp5
    disableNonEssentialServices = true;
    lowJitter = false;
    managementInterface = "eno1";

    # No Flow Director rules wired by default on the mlx5 pair yet.
    # The mlx5_core branch uses tc-flower for steering (see xdp2
    # nix/modules/nic-tuning.nix § mlx5_core); when the ntuple+template
    # bench is brought up on hp1↔hp3, add rules here matching hp2/hp5.
    flowDirectorRules = [ ];
    realServicesBench = false;
  };

  # mlx5_core selects the Mellanox NIC tuning branch in
  # xdp2.nicTuning (tc-flower steering, mlx5_comp* IRQ pinning).
  # Override the i40e default that physical-testbed.nix forwards.
  xdp2.nicTuning.driver = "mlx5_core";

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

  networking.hostName = "hp3";

  services.lldpd.enable = true;

  networking.networkmanager.enable = false;

  # Explicit nameservers — DHCP from the LAN gateway has been observed
  # to land an empty resolv.conf, breaking nix-binary-cache fetches
  # (xdp2 docs/physical-testbed.md §3, hp5 incident 2026-04-20).
  networking.nameservers = [ "172.16.40.1" "1.1.1.1" "8.8.8.8" ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" "video" "nginx" ];
    packages = with pkgs; [
    ];
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

  # Keep at 24.05 to match the existing hp3 install; do not bump unless
  # you're prepared to migrate stateful services.
  system.stateVersion = "24.05";

  # Show fastfetch before login prompt
  services.getty.loginProgram = let
    loginWrapper = pkgs.writeShellScript "login-with-fastfetch" ''
      ${pkgs.fastfetch}/bin/fastfetch
      echo ""
      exec ${pkgs.shadow}/bin/login "$@"
    '';
  in "${loginWrapper}";
}
