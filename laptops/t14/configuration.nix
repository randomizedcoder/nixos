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

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.05.tar.gz home-manager
      # sudo nix-channel --update
      <home-manager/nixos>
      #
      ./sysctl.nix
      ./wireless_desktop.nix
      ./sound.nix
      ./locale.nix
      ./hosts.nix
      ./firewall.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      ./home-manager.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      # clickhouse
      #./docker-compose.nix
      ./docker-daemon.nix
      #./smokeping.nix
    ];



  # Bootloader.
  boot.loader.systemd-boot = {
    enable = true;
    consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
    memtest86.enable = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPackages = pkgs.linuxPackages_rpi4

  #boot.kernelParams = [
  # https://github.com/tolgaerok/nixos-2405-gnome/blob/main/core/boot/efi/efi.nix#L56C5-L56C21

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
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "t14";

  services.lldpd.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  services.xserver = {
    enable = true;

    # Display Managers are responsible for handling user login
    displayManager = {
      gdm.enable = true;
    };
    # Enable the GNOME Desktop Environment.
    desktopManager = {
      gnome.enable = true;
      plasma5.enable = false;
      xterm.enable = false;
    };
    # https://discourse.nixos.org/t/help-with-setting-up-a-different-desktop-environment-window-manager/15025/6

    # Configure keymap in X11
    xkb.layout = "us";
    xkb.variant = "";
  };

  #[das@t:~]$ lshw -c video | grep config
  #WARNING: you should run this program as super-user.
  #       configuration: depth=32 driver=nouveau latency=0 resolution=3840,2160
  #       configuration: depth=32 driver=i915 latency=0 resolution=3840,2160
  #
  #[das@t:~]$ lspci -nnk | egrep -i --color 'vga|3d|2d' -A3 | grep 'in use'
  #Kernel driver in use: i915
  #Kernel driver in use: nouveau
  #
  #[das@t:~]$ lspci -nnk | grep -i vga -A2
  #00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-H GT2 [UHD Graphics] [8086:9bc4] (rev 05)
  #Subsystem: Lenovo Device [17aa:22c0]
  #Kernel driver in use: i915
  #--
  #01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117GLM [Quadro T2000 Mobile / Max-Q] [10de:1fb8] (rev a1)
  #Subsystem: Lenovo Device [17aa:22c0]
  #Kernel driver in use: nouveau
  #
  # hwinfo --gfxcard


  services.udev.packages = [ pkgs.gnome.gnome-settings-daemon ];

  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
    #ANOTHER_VARIABLE = "another-value";
  };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
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
    pciutils
    virt-manager
    #cudatoolkit #t14 is not nvidia
    pkgs.gnomeExtensions.appindicator
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

  #programs.hyprland.enable = true;

  services.openssh.enable = true;

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  #system.stateVersion = "23.11";
  system.stateVersion = "24.05";

  virtualisation.containers = {
    ociSeccompBpfHook.enable = true;
  };

  # # https://nixos.wiki/wiki/Podman
  # virtualisation.podman = {
  #   enable = true;
  #   dockerCompat = true;
  #   defaultNetwork.settings.dns_enabled = true;
  #   autoPrune.enable = true;
  # };
  # #virtualisation.oci-containers.backend = "podman";
  # # virtualisation.oci-containers.containers = {
  # #   container-name = {
  # #     image = "container-image";
  # #     autoStart = true;
  # #     ports = [ "127.0.0.1:1234:1234" ];
  # #   };
  # # };

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  # services.qemuGuest.enable = true;

  # https://wiki.nixos.org/wiki/Laptop
}
