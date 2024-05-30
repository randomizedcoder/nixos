# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# sudo nixos-rebuild switch
# nix-shell -p vim
# nmcli device wifi connect MYSSID password PWORD
# systemctl restart display-manager.service

{ config, pkgs, ... }:

# https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz home-manager
      # sudo nix-channel --update
      <home-manager/nixos>
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "hp0"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.wireless = {
    enable = true;  # Enables wireless support via wpa_supplicant.
    environmentFile = "/home/das/wireless.env";
    networks."devices".psk = "performance";
    #networks."devices".psk = "@PSK_DEVICES@";
    extraConfig = "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel";
    # output ends up in /run/wpa_supplicant/wpa_supplicant.conf
  };
  # https://linux.die.net/man/5/wpa_supplicant.conf
  # https://nixos.wiki/wiki/Wpa_supplicant
  # https://nixos.org/manual/nixos/stable/options#opt-networking.wireless.environmentFile
  # https://blog.stigok.com/2021/05/04/getting-wpa-cli-to-work-in-nixos.html

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = false;
  #networking.networkmanager.enable = true;

  networking.hosts = {
    "172.16.40.198" = ["hp0"];
  #   "172.16.40.35" = ["hp1"];
  #   "172.16.40.71" = ["hp2"];
    "172.16.40.146" = ["hp3"];
  };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "libvirtd" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  users.users.eve.isNormalUser = true;
  home-manager.users.das = { pkgs, ... }: {
    home.packages = with pkgs; [
      #
      tmux
      screen
      #
      perl
      python3
      #
      gawk
      jq
      git
      htop
      minicom
      #
      iproute2
      vlan
      tcpdump
      wireshark
      flent
      iperf2
      bpftools
      iw
      wirelesstools
      wpa_supplicant_ro_ssids
      # go
      # https://nixos.wiki/wiki/Go
      # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
      # https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
      libcap
      gcc
      #  thunderbird
      go
      # rust
      # https://nixos.wiki/wiki/Rust
      pkgs.cargo
      pkgs.rustc
    ];

    programs.bash.enable = true;
    home.stateVersion = "23.11";

    programs.vim = {
      enable = true;
      plugins = with pkgs.vimPlugins; [ vim-airline ];
      settings = { ignorecase = true; };
      extraConfig = ''
        set mouse=a
      '';
    };
    #ldflags = [
    #  "-X main.Version=${version}"
    #  "-X main.Commit=${version}"
    #];

    programs.git = {
      enable = true;
      userEmail = "dave.seddon.ca@gmail.com";
      userName = "randomizedcoder ";
      #signing.key = "GPG-KEY-ID";
      #signing.signByDefault = true;
    };
    nixpkgs.config.allowUnfree = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    vim
    curl
    wget
    tcpdump
    iproute2
    nftables
    iptables
    pciutils
    usbutils
    iw
    wirelesstools
    wpa_supplicant_ro_ssids
  ];

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

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # https://nixos.wiki/wiki/Firewall
  # https://scvalex.net/posts/54/
  # nft --stateless list table filter
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22     # ssh
      5001   # iperf2
    ];
  #   allowedTCPPorts = [ 22 5001 ];
  #   #allowedUDPPortRanges = [
  #   #  { from = 4000; to = 4007; }
  #   #  { from = 8000; to = 8010; }
  #   #];
  };
  # networking.firewall.interfaces."eth0".allowedTCPPorts = [ 80 443 ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

  # virtualisation.libvirtd.enable = true;
  # programs.virt-manager.enable = true;
  # services.qemuGuest.enable = true;

  # https://wiki.nixos.org/wiki/Laptop

}
