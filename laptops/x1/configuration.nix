# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
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
      #./prometheus.nix
      #./grafana.nix
      # clickhouse
      #./docker-compose.nix
      #./docker-daemon.nix
      #./smokeping.nix
      #./x.nix
    ];

  boot = {
    loader.grub.enable = true;
    loader.grub.device = "/dev/sda";
    loader.grub.useOSProber = true;

    # loader.systemd-boot = {
    #   enable = true;
    #   consoleMode = "max";
    #   memtest86.enable = true;
    # };

    loader.efi.canTouchEfiVariables = true;

    initrd.luks.devices."luks-4e0b3033-8dbb-4826-a5ad-519bef35cace".device = "/dev/disk/by-uuid/4e0b3033-8dbb-4826-a5ad-519bef35cace";

    initrd.secrets = {
      "/boot/crypto_keyfile.bin" = null;
    };

    loader.grub.enableCryptodisk = true;

    initrd.luks.devices."luks-b6b13ee4-ca25-49d1-a927-a90d56446a3d".keyFile = "/boot/crypto_keyfile.bin";
    initrd.luks.devices."luks-4e0b3033-8dbb-4826-a5ad-519bef35cace".keyFile = "/boot/crypto_keyfile.bin";
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
    };
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "daily";                   # Schedule the task to run daily
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

  networking.hostName = "x1";
  #networking.wireless.enable = true; # using network manager

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  users.users.test = {
    isNormalUser = true;
    description = "test";
    extraGroups = [ "networkmanager" ];
    packages = with pkgs; [
      firefox
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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

  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
