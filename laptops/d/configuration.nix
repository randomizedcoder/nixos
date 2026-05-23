# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

# sudo nixos-rebuild switch --flake .#d
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

{
  # https://nixos.wiki/wiki/NixOS_modules
  # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
  imports =
    [
      ./hardware-configuration.nix
      ./hardware-graphics-intel.nix
      ./sysctl.nix
      ./wireless_desktop.nix
      ./locale.nix
      ./hosts.nix
      ./firewall.nix
      ./systemPackages.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      ./clickhouse-service.nix
      ./docker-daemon.nix
      ./nginx.nix
      ./below.nix
      # BBRv3 congestion control from L4S team
      ./bbr3-module.nix
      # On-demand AnyConnect VPN via OpenConnect
      ./openconnect-vpn.nix
      # On-demand NordLayer VPN via OpenVPN
      ./nordlayer-vpn.nix
      # Direct OpenVPN connection to NordLayer (alternative to the
      # proprietary daemon above — coexists, autoStart=false).
      ./nordlayer-openvpn.nix
      # Lets LAN traffic survive nordlayer's kill-switch (SSH between
      # machines on the local network while the VPN is connected).
      ./nordlayer-lan-bypass.nix
    ];

  boot = {

    loader.systemd-boot = {
      enable = true;
      consoleMode = "max";
      memtest86.enable = true;
      configurationLimit = 20;
    };

    loader.efi.canTouchEfiVariables = true;

    # Latest mainline kernel — fine on Intel-only laptop (no NVIDIA constraint).
    # Meteor Lake media/Xe driver support improves with newer kernels.
    kernelPackages = pkgs.linuxPackages_latest;

    # https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
    binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];

    # Nested virtualisation for libvirtd.
    extraModprobeConfig = ''
      options kvm_intel nested=1
    '';
  };

  # https://fzakaria.com/2025/02/26/nix-pragmatism-nix-ld-and-envfs
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libxml2
      pciutils
      libdrm
    ];
  };

  services.envfs = {
    enable = true;
  };

  security.polkit.enable = true;

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
      trusted-users = [ "das" ];
      http-connections = 100;
      max-substitution-jobs = 64;
      # Meteor Lake-P laptop — typical 16-thread configuration.
      # Override per-command with: nix build --option cores N -j M
      max-jobs = 1;
      cores = 16;
    };
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 10d";
      randomizedDelaySec = "14m";
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "d";

  time.timeZone = "America/Los_Angeles";

  services.udev.packages = [ pkgs.gnome-settings-daemon ];

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  environment.sessionVariables = {
    TERM = "xterm-256color";
    PIPEWIRE_SCREEN_CAPTURE = "1";
    QT_QPA_PLATFORM = "wayland";
  };

  # fix for /bin/sh for the claude bug
  environment.binsh = "${pkgs.bash}/bin/bash";

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

  # Bluetooth — laptops generally want this on.
  hardware.bluetooth.enable = true;

  # Disable ModemManager — conflicts with NetworkManager on laptops.
  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" "pipewire" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  services.xserver = {
    enable = true;
    videoDrivers = [ "modesetting" ];
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
    ];
    config.common.default = "gnome";
    config.gnome.default = "gnome";
  };

  services.dbus.packages = with pkgs; [
    xdg-desktop-portal
    xdg-desktop-portal-gtk
  ];

  # https://nixos.wiki/wiki/Virt-manager
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  virtualisation.containers = {
    ociSeccompBpfHook.enable = true;
  };

  # https://wiki.nixos.org/wiki/Laptop

  # BBRv3 congestion control from L4S team (out-of-tree module)
  services.bbr3.enable = true;

  # State version locked to the fresh-install release; do NOT change this.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";

}

# end
