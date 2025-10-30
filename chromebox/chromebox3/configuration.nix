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
    [
      ./disko-chromebox3.nix
      ./sysctl.nix
      ./il8n.nix
      ./systemPackages.nix
      ./hosts.nix
      ./nodeExporter.nix
      #./docker-daemon.nix
      #./k8s_master.nix
      #./k3s_master.nix
      #./k3s_node.nix
      # Modular Kubernetes configuration
      ./kubernetes.nix
      ./kubernetes_addonManager.nix
      ./kubernetes_etcd.nix
      ./kubernetes_networking.nix
      ./kubernetes_runtime.nix
    ];

  # boot.loader.grub = {
  #   # no need to set devices, disko will add all devices that have a EF02 partition to the list already
  #   # devices = [ ];
  #   efiSupport = true;
  #   efiInstallAsRemovable = true;
  # };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  #boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  boot.kernelPackages = pkgs.linuxPackages;
  #boot.kernelPackages = pkgs.linuxPackages_latest;

  nix = {
    gc = {
      automatic = true;                     # Enable automatic execution of the task
      dates = "weekly";                     # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";           # Introduce a randomized delay of up to 14 minutes before executing the task
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  # https://nixos.wiki/wiki/Networking
  # https://nlewo.github.io/nixos-manual-sphinx/configuration/ipv4-config.xml.html
  networking.hostName = "chromebox3";

  services.lldpd.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.networkmanager.enable = false;

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
    password = "admin123";
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" ];
    # packages = with pkgs; [
    # ];
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

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

  # virtualisation.libvirtd.enable = true;
  # programs.virt-manager.enable = true;
  # services.qemuGuest.enable = true;

  # https://wiki.nixos.org/wiki/Laptop
}
