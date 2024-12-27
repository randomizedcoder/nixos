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
      # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz home-manager
      # sudo nix-channel --update
      <home-manager/nixos>
      #
      ./sysctl.nix
      ./wireless.nix
      ./hosts.nix
      ./firewall.nix
      ./il8n.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      ./home-manager.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      #./trafficserver.nix
    ];

  # https://nixos.wiki/wiki/Nix_Cookbook
  nix.gc.automatic = true;
  nix.settings.auto-optimise-store = true;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # https://nixos.wiki/wiki/Linux_kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPackages = pkgs.linuxPackages_rpi4

  # https://nixos.wiki/wiki/Networking
  # https://nlewo.github.io/nixos-manual-sphinx/configuration/ipv4-config.xml.html
  networking.hostName = "hp4";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.networkmanager.enable = false;

  networking.interfaces.enp1s0f0.useDHCP = false;
  networking.interfaces.enp1s0f0np0.useDHCP = false;
  networking.interfaces.enp1s0f1.useDHCP = false;
  networking.interfaces.enp1s0f1np1.useDHCP = false;
  boot.kernel.sysctl."net.ipv6.conf.enp1s0f0.disable_ipv6" = true;
  boot.kernel.sysctl."net.ipv6.conf.enp1s0f0np0.disable_ipv6" = true;
  boot.kernel.sysctl."net.ipv6.conf.enp1s0f1.disable_ipv6" = true;
  boot.kernel.sysctl."net.ipv6.conf.enp1s0f1np1.disable_ipv6" = true;
  # networking.interfaces.enp1s0f0.ipv4.addresses = [{
  #   address = "76.174.138.10";
  #   prefixLength = 24;
  # }];

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
    extraGroups = [ "wheel" "networkmanager" "libvirtd" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOP3x3r8OZ5ya1GNLqmKOsKDX7oAR+BG9u4EozXvydtC das@hp0"
    ];
  };

  # # https://mynixos.com/options/users.users.%3Cname%3E
  # users.users._lldpd = {
  #   group = "_lldpd";
  #   isNormalUser = false; # one of these must be set
  #   isSystemUser = true;
  #   description = "LLDPd";
  #   createHome = false;
  # };
  # users.groups._lldpd = {};
  services.lldpd.enable = true;

  # # https://github.com/lldpd/lldpd/blob/2151a7d056a626132273aadfb7022547b076d010/README.md?plain=1#L51
  # systemd.tmpfiles.rules =
  # [
  #   "d /usr/local/var/run/lldpd 755 root root"
  # ];

  systemd.services.snmpd = {
    enable           = true;
    wantedBy         = [ "multi-user.target" ];
    description      = "Net-SNMP daemon";
    after            = [ "network.target" ];
    restartIfChanged = true;
    # serviceConfig = {
    #   User         = "root";
    #   Group        = "root";
    #   Restart      = "always";
    #   ExecStart    = "${pkgs.net-snmp}/bin/snmpd -Lf /var/log/snmpd.log -f -c /etc/snmp/snmpd.conf";
    # };
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

  # https://nixos.wiki/wiki/SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # TODO DISABLE THIS!!!
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

  # virtualisation.libvirtd.enable = true;
  # programs.virt-manager.enable = true;
  # services.qemuGuest.enable = true;

  # https://wiki.nixos.org/wiki/Laptop
}
