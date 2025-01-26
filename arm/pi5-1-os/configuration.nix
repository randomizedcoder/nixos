#
# nixos/arm/pi5-1-os
#

#{ config, lib, pkgs, ... }:
{ inputs, config, lib, pkgs, ... }:

{
  imports = [
      #./hardware-configuration.nix
      ./il8n.nix
      ./nodeExporter.nix
      ./hosts.nix
      ./docker-daemon.nix
    ];

  # Use the GRUB 2 boot loader.
  #boot.loader.grub.enable = false;
  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  # boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only
  # Enables the generation of /boot/extlinux/extlinux.conf
  #boot.loader.generic-extlinux-compatible.enable = true;

  #boot.loader.efi.canTouchEfiVariables = false;

  # kernel comes from the community package
  # https://nixos.wiki/wiki/Linux_kernel
  #boot.kernelPackages = pkgs.linuxPackages;
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPackages = pkgs.linuxPackages_rpi5;
  #boot.kernelPackages = (import (builtins.fetchTarball https://gitlab.com/vriska/nix-rpi5/-/archive/main.tar.gz)).legacyPackages.aarch64-linux.linuxPackages_rpi5;

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
      # https://gitlab.com/engmark/root/-/merge_requests/785/diffs
      download-buffer-size = "500000000";
    };
  };

  networking.hostName = "pi5-1";

  networking.networkmanager.enable = false;

  services.lldpd.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  time.timeZone = "America/Los_Angeles";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" ];
    # users.extraGroups.docker.members = [ "das" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
    #ANOTHER_VARIABLE = "another-value";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    htop
    btop
    neofetch
    tcpdump
    iproute2
    hw-probe
    lshw
    gnumake
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "24.11"; # Did you read the comment?

}

