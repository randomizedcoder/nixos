#
# hp/hp1/configuration.nix
#
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
      ./networkd.nix
      ./firewall.nix
      ./il8n.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported by the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      #./docker-daemon.nix
      #./k8s_master.nix
      #./k8s_node.nix
      #./k3s_master.nix
      #./k3s_node.nix

      # Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller
      #./systemd.services.ethtool-eno1.nix # rings are not adjustable
      # Intel Corporation Ethernet Controller 10-Gigabit X540-AT2
      ./systemd.services.ethtool-enp1s0f0.nix
      ./systemd.services.ethtool-enp1s0f1.nix
      # Intel Corporation 82571EB/82571GB Gigabit Ethernet Controller D0/D1 (copper applications)
      ./systemd.services.ethtool-enp4s0f0.nix
      ./systemd.services.ethtool-enp4s0f1.nix
      # Bridge enp1s0f0 and enp1s0f1 together
      ./systemd.services.bridge.nix
      #./ffmpeg_systemd_service.nix
      #./firewall-test-phase1.nix
    ];

# https://nixos.wiki/wiki/Kubernetes#reset_to_a_clean_state
# rm -rf /var/lib/kubernetes/ /var/lib/etcd/ /var/lib/cfssl/ /var/lib/kubelet/
# rm -rf /etc/kube-flannel/ /etc/kubernetes/
# rm -rf /var/lib/kubernetes/ /var/lib/etcd/ /var/lib/cfssl/ /var/lib/kubelet/ /etc/kube-flannel/ /etc/kubernetes/

  # Bootloader.
  boot = {
    loader.systemd-boot = {
      enable = true;
      #consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
      memtest86.enable = true;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/AMD_GPU
    initrd.kernelModules = [ "amdgpu" ];

    # https://nixos.wiki/wiki/Linux_kernel
    kernelPackages = pkgs.linuxPackages_latest;
    #boot.kernelPackages = pkgs.linuxPackages_rpi4
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "100000000";
      builders-use-substitutes = true;
    };
    # # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#set-up-distributed-builds
    # distributedBuilds = true;
    # buildMachines = [{
    #   hostName = "hp4";
    #   sshUser = "remotebuild";
    #   #sshKey = "/root/.ssh/remotebuild";
    #   sshKey = "/home/das/.ssh/remotebuild";
    #   system = pkgs.stdenv.hostPlatform.system;
    #   supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
    # }];
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "weekly";                  # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

  # # find /run/opengl-driver -name "libamfrt64.so.1"
  # hardware.graphics = {
  #   enable = true;
  #   extraPackages = with pkgs; [
  #     amdvlk  # AMD Vulkan driver, includes AMF runtime
  #     #rocm-opencl-runtime  # Optional: ROCm OpenCL support
  #     #rocm-smi  # AMD System Management Interface (for monitoring GPU)
  #     # https://nixos.wiki/wiki/AMD_GPU#OpenCL
  #     rocmPackages.clr.icd
  #   ];
  # };

  services.xserver.videoDrivers = [ "amdgpu" ];

  # https://nixos.wiki/wiki/Networking
  # https://nlewo.github.io/nixos-manual-sphinx/configuration/ipv4-config.xml.html
  networking.hostName = "hp1";

  # Network configuration is now handled by systemd-networkd (see networkd.nix)
  # Legacy interface configuration removed - use systemd-networkd instead

  services.lldpd.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # NetworkManager disabled - using systemd-networkd instead
  networking.networkmanager.enable = false;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
    #ANOTHER_VARIABLE = "another-value";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" "video" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOP3x3r8OZ5ya1GNLqmKOsKDX7oAR+BG9u4EozXvydtC das@hp0"
    ];
  };

  # # https://github.com/colemickens/nixcfg/blob/1915d408ea28a5b7279f94df7a982dbf2cf692ef/mixins/ssh.nix#L13C1-L28C7
  # system.activationScripts.root_ssh_config = {
  #   text = ''
  #     (
  #       # symlink root ssh config to ours so daemon can use our agent/keys/etc...
  #       mkdir -p /root/.ssh
  #       ln -sf /home/das/.ssh/config /root/.ssh/config
  #       ln -sf /home/das/.ssh/known_hosts /root/.ssh/known_hosts
  #       ln -sf /home/das/.ssh/known_hosts /root/.ssh/known_hosts
  #     )
  #   '';
  #   deps = [ ];
  # };

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


  # https://nixos.wiki/wiki/SSH
  services.openssh.enable = true;

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  # AMD GPU power management
  #services.udev.packages = with pkgs; [ rocm-smi ];

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

  # https://wiki.nixos.org/wiki/Laptop
}
