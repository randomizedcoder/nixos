#
# qotom/nfb/configuration.nix
#
{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix

      ./nix.nix

      ./sysctl.nix
      ./il8n.nix
      ./systemPackages.nix

      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix

      ./systemd.services.ethtool-set-ring.nix

      ./nginx.nix

      ./services.ssh.nix
      ./services.ssh-google-auth.nix
      ./services.freeradius.nix

      ./smokeping.nix
      ./pdns-recursor.nix

      ./atftpd.nix

      ./network.nix
      ./serial-tty.nix

      ./chrony.nix
    ];

  boot = {

    loader.systemd-boot = {
      enable = true;
      consoleMode = "max";
      memtest86.enable = true;
      configurationLimit = 20;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/Linux_kernel
    #kernelPackages = pkgs.linuxPackages;
    kernelPackages = pkgs.linuxPackages_latest;
  };

  networking.hostName = "nfbQotom";
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  # networking.networkmanager.enable = true;  # Disabled - using systemd-networkd instead

  services.lldpd.enable = true;
  # timesyncd is disabled in chrony.nix to avoid conflicts
  services.fstrim.enable = true;

  time.timeZone = "America/Los_Angeles";


  users.users.das = {
    isNormalUser = true;
    description = "das";
    # dailout for serial: https://wiki.nixos.org/wiki/Serial_Console#Unprivileged_access_to_serial_device
    extraGroups = [ "wheel" "dialout" ];
    packages = with pkgs; [];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  users.users.nigel = {
    isNormalUser = true;
    description = "nigel";
    extraGroups = [ "wheel" "dialout" ];
    packages = with pkgs; [];
  };

  nixpkgs.config.allowUnfree = true;

  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  system.stateVersion = "25.05"; # Did you read the comment?

}
