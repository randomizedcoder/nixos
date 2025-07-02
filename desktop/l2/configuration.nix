#
#
# l2/configuration.nix
#

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
      ./disko-l2.nix
      ./hardware-configuration.nix
      #./hardware-graphics.nix
      ./sysctl.nix
      #./wireless_desktop.nix
      ./locale.nix
      ./hosts.nix
      ./firewall.nix
      ./crowdsec.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported in the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      # clickhouse
      #./docker-compose.nix
      #./docker-daemon.nix
      #./smokeping.nix
      #./distributed-builds.nix
      #./hyprland.nix
      #./hostapd.nix
      ./hostapd-multi.nix
      ./network-optimization.nix
      # CPU and IRQ optimization modules
      ./irq-affinity.nix
      ./systemd-slices.nix
      ./kernel-params.nix
      #./monitoring.nix
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

    initrd.kernelModules = [
      "amdgpu"
    ];

    blacklistedKernelModules = [
      "nouveau"
      #"i915"
    ];

    initrd.preDeviceCommands = ''
      echo "Loading regulatory database early"
      cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db /lib/firmware/
      cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db.p7s /lib/firmware/
    '';

    # cat /proc/cmdline
    # cat /etc/modprobe.d/nixos.conf
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom=US
      options iwlwifi lar_disable=1
    '';

  };

  # https://fzakaria.com/2025/02/26/nix-pragmatism-nix-ld-and-envfs
  # Enable nix-ld for better compatibility with non-Nix binaries
  programs.nix-ld = {
    enable = true;
    # Add commonly needed libraries
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libxml2
    ];
  };

  # Enable envfs for better compatibility with FHS expectations
  services.envfs = {
    enable = true;
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
      # https://nix.dev/manual/nix/2.28/command-ref/conf-file#conf-max-jobs
      max-jobs = 12; # default = 1.  Setting this to 1/2 my cores
      http-connections = 100; # default 25
      # https://nix.dev/manual/nix/2.28/command-ref/conf-file#conf-max-substitution-jobs
      max-substitution-jobs = 64; # default 16
    };
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "daily";                   # Schedule the task to run daily
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "l2";

  time.timeZone = "America/Los_Angeles";

  systemd.services.systemd-udev-settle.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "yes"; # Change me to "no"!!
      #AllowUsers = [ "das" ]
    };
  };

  programs.ssh.extraConfig = ''
  Host hp4.home
    PubkeyAcceptedKeyTypes ssh-ed25519
    ServerAliveInterval 60
    IPQoS throughput
  '';

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

  # environment.variables defined in hardware-graphics.nix
  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
  };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    password = "admin123"; # FIX ME!!
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" ];
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

  # # https://nixos.wiki/wiki/Virt-manager
  # virtualisation.libvirtd.enable = true;
  # #programs.virt-manager.enable = true;
  # virtualisation.spiceUSBRedirection.enable = true;

  # virtualisation.containers = {
  #   ociSeccompBpfHook.enable = true;
  # };

  #system.stateVersion = "24.11";
  system.stateVersion = "25.05";

  systemd.extraConfig = "CPUAffinity=8,20,9,21,10,22,11,23";
  systemd.user.extraConfig = "CPUAffinity=8,20,9,21,10,22,11,23";

}

# end