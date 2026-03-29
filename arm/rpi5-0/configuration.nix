#
# nixos/arm/rpi5-0
#

{ config, lib, pkgs, ... }:

{
  imports = [
    ./il8n.nix
    ./nodeExporter.nix
    ./hosts.nix
    ./docker-daemon.nix
  ];

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
      download-buffer-size = "500000000";
    };
  };

  networking.hostName = "rpi5-0";
  networking.networkmanager.enable = false;

  services.lldpd.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" ];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  environment.sessionVariables = {
    TERM = "xterm-256color";
  };

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

  services.openssh.enable = true;
  services.timesyncd.enable = true;
  services.fstrim.enable = true;

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
