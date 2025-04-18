# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# sudo nixos-rebuild switch
# sudo nix-channel --update
# nix-shell -p vim
# nmcli device wifi connect MYSSID password PWORD
# systemctl restart display-manager.service

{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

# https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
# https://discourse.nixos.org/t/differences-between-nix-channels/13998

{
  # https://nixos.wiki/wiki/NixOS_modules
  # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
  imports =
    [
      ./hardware-configuration.nix
      #./hardware-graphics.nix
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
      ./prometheus.nix
      ./grafana.nix
      # clickhouse
      #./docker-compose.nix
      ./docker-daemon.nix
      #./smokeping.nix
      ./x.nix
    ];

  boot = {

    loader.systemd-boot = {
      enable = true;
      consoleMode = "max";
      memtest86.enable = true;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/Linux_kernel
    #kernelPackages = pkgs.linuxPackages; # need to run this old kernel to allow nvidia driver to compile :(
    #kernelPackages = pkgs.unstable.linuxPackages;
    kernelPackages = pkgs.linuxPackages_latest;
    #boot.kernelPackages = pkgs.linuxPackages_rpi4

    # https://github.com/tolgaerok/nixos-2405-gnome/blob/main/core/boot/efi/efi.nix#L56C5-L56C21
    kernelParams = [
      #"nvidia-drm.modeset=1"
      #"nvidia-drm.fbdev=1"
      # https://www.reddit.com/r/NixOS/comments/u5l3ya/cant_start_x_in_nixos/?rdt=56160
      #"nomodeset"
    ];

    #blacklistedKernelModules = [
    #  "nouveau"
    #  #"i915"
    #];

    # https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
    # https://nixos.org/manual/nixos/stable/options#opt-boot.binfmt.emulatedSystems
    binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];

    extraModulePackages = with config.boot.kernelPackages; [
      v4l2loopback
      #nvidia_x11
    ];

    # # https://nixos.wiki/wiki/Libvirt#Nested_virtualization
    # #extraModprobeConfig = "options kvm_intel nested=1";
    # # https://gist.github.com/chrisheib/162c8cad466638f568f0fb7e5a6f4f6b#file-config_working-nix-L19
    # extraModprobeConfig =
    #   "options nvidia "
    #   #""
    #   + lib.concatStringsSep " " [
    #   # nvidia assume that by default your CPU does not support PAT,
    #   # but this is effectively never the case in 2023
    #   "NVreg_UsePageAttributeTable=1"
    #   # This is sometimes needed for ddc/ci support, see
    #   # https://www.ddcutil.com/nvidia/
    #   #
    #   # Current monitor does not support it, but this is useful for
    #   # the future
    #   "NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100"
    #   "options kvm_intel nested=1"
    #   # # https://nixos.wiki/wiki/OBS_Studio
    #   ''
    #     options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    #   ''
    # ];
  };

  # For OBS
  security.polkit.enable = true;

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
      download-buffer-size = "500000000";
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "t14";

  time.timeZone = "America/Los_Angeles";

  services.udev.packages = [ pkgs.gnome-settings-daemon ];
  # services.udev.packages = [ pkgs.gnome.gnome-settings-daemon ];

  # https://nixos.wiki/wiki/NixOS_Wiki:Audio
  hardware.pulseaudio.enable = false; # Use Pipewire, the modern sound subsystem

  security.rtkit.enable = true; # Enable RealtimeKit for audio purposes

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # Uncomment the following line if you want to use JACK applications
    # jack.enable = true;
  };

  services.lldpd.enable = true;
  services.openssh.enable = true;
  services.timesyncd.enable = true;
  services.fstrim.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  services.bpftune.enable = true;
  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # https://nixos.wiki/wiki/Printing
  services.printing.enable = true;

  # https://wiki.nixos.org/wiki/Flameshot
  # services.flameshot = {
  #   enable = true;
  #   settings.General = {
  #     showStartupLaunchMessage = false;
  #     saveLastRegion = true;
  #   };
  # };

  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  services.clickhouse.enable = false;
  # https://nixos.wiki/wiki/PostgreSQL
  services.postgresql.enable = true;
  # https://nixos.wiki/wiki/Mysql
  services.mysql.package = pkgs.mariadb;
  services.mysql.enable = true;

  # environment.variables defined in hardware-graphics.nix
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

  # package moved to systemPackages.nix
  # environment.systemPackages = with pkgs; [

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # # https://wiki.hyprland.org/Nix/Hyprland-on-NixOS/
  programs.hyprland = {
    enable = true;
    # Nvidia patches are no longer needed
    #nvidiaPatches = true;
    xwayland.enable = true;
  };
  # programs.hyprland = {
  #   enable = true;
  #   # set the flake package
  #   package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  #   # make sure to also set the portal package, so that they are in sync
  #   portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  # };

  # programs.chromium.enable = true;
  # # programs.chromium.package = pkgs.google-chrome;
  # # https://nixos.wiki/wiki/Chromium#Enabling_native_Wayland_support
  # nixpkgs.config.chromium.commandLineArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland";
  # #programs.chromium.commandLineArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland";

  # programs.firefox.enable = true;
  # # # https://github.com/TLATER/dotfiles/blob/master/nixos-modules/nvidia/default.nix
  # programs.firefox.preferences = {
  #   "media.ffmpeg.vaapi.enabled" = true;
  #   "media.rdd-ffmpeg.enabled" = true;
  #   "media.av1.enabled" = true; # Won't work on the 2060
  #   "gfx.x11-egl.force-enabled" = true;
  #   "widget.dmabuf.force-enabled" = true;
  # };

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

  # https://nixos.wiki/wiki/Virt-manager
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # guest
  # services.qemuGuest.enable = true;
  # services.spice-vdagentd.enable = true;

  nixpkgs.config.allowUnfree = true;

  # https://wiki.nixos.org/wiki/Laptop
}
