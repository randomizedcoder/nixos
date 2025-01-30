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
      ./docker-daemon.nix
      #./k8s_master.nix
      #./k8s_node.nix
      #./k3s_master.nix
      ./k3s_node.nix
      ./systemd.services.ethtool-enp3s0f0.nix
      ./systemd.services.ethtool-enp3s0f1.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot = {
    enable = true;
    #consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
    memtest86.enable = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelPackages = pkgs.linuxPackages;
  #boot.kernelPackages = pkgs.linuxPackages_4_19; # 4.19.319
  #boot.kernelPackages = pkgs.linuxPackages_5_4; # 5.4.281
  #boot.kernelPackages = pkgs.linuxPackages_5_15; # 5.15.164
  #boot.kernelPackages = pkgs.linuxPackages_6_1; # 6.1.103
  #boot.kernelPackages = pkgs.linuxPackages_6_8; # 6.8
  #boot.kernelPackages = pkgs.linuxPackages_6_10; # 6.10

  boot.blacklistedKernelModules = [ "nouveau" ];

  boot.extraModulePackages = with config.boot.kernelPackages; [
    nvidia_x11
  ];

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

  time.timeZone = "America/Los_Angeles";


  # hardware.opengl.enable = true;
  # was renamed to:
  hardware.graphics = {
    enable = true;
    # P620
    # Linux x64 (AMD64/EM64T) Display Driver 535.146.02 | Linux 64-bit
    # https://www.nvidia.com/en-us/drivers/details/216820/
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/os-specific/linux/nvidia-x11/default.nix
    # version = "535.154.05";
    # package = config.boot.kernelPackages.nvidiaPackages.dc_535;
    # version = "535.216.01";
    #package = config.boot.kernelPackages.nvidiaPackages.legacy_535;
    extraPackages = with pkgs; [
      vdpauinfo             # sudo vainfo
      libva-utils           # sudo vainfo
      # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
      nvidia-vaapi-driver
      vaapiVdpau
    ];
  };

  # https://wiki.nixos.org/w/index.php?title=NVIDIA
  # https://nixos.wiki/wiki/Nvidia
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/hardware/video/nvidia.nix
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/hardware/video/nvidia.nix
  hardware.nvidia = {
    # https://github.com/NixOS/nixpkgs/pull/326369 hits stable
    modesetting.enable = true;
    powerManagement = {
      enable = true;
    };
    nvidiaSettings = true;
  };

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
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" ];
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

  services.openssh.enable = true;


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

  # https://wiki.nixos.org/wiki/Laptop
}
