#
# hp/hp4/configuration.nix
#

# sudo nixos-rebuild switch
# sudo nix-channel --update
# nix-shell -p vim
# nmcli device wifi connect MYSSID password PWORD
# systemctl restart display-manager.service

{ config, pkgs, lib, ... }:

# https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
# https://discourse.nixos.org/t/differences-between-nix-channels/13998

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.11.tar.gz home-manager
      # sudo nix-channel --update
      # tutorial
      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
      #<home-manager/nixos>
      #
      ./sysctl.nix
      # ./wireless.nix
      ./hosts.nix
      ./firewall.nix
      ./il8n.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported by the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      ./docker-daemon.nix
      #./k8s_master.nix
      #./k8s_node.nix
      #./k3s_master.nix
      #./k3s_node.nix
      ./systemd.services.ethtool-enp1s0f0.nix
      ./systemd.services.ethtool-enp1s0f1.nix
      ./nginx.nix
      ./trafficserver.nix
      ./athens.nix
      ./remote-builder.nix
      ./services.ssh.nix
      ./smokeping.nix
      ./blackbox.nix
      ./pdns-recursor.nix
    ];

  # Bootloader.
  boot = {
    loader.systemd-boot = {
      enable = true;
      #consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
      memtest86.enable = true;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/AMD_GPU
    #initrd.kernelModules = [ "amdgpu" ];

    # https://nixos.wiki/wiki/Linux_kernel
    kernelPackages = pkgs.linuxPackages_latest;
    #boot.kernelPackages = pkgs.linuxPackages_rpi4
  };

  # https://nixos.wiki/wiki/Nix_Cookbook
  nix = {
    nrBuildUsers = 64;
    settings = {
      auto-optimise-store = true;
      #experimental-features = [ "nix-command" "flakes" ];
      experimental-features = [ "nix-command" "flakes" "configurable-impure-env" ];
      #impure-env = "GOPROXY=http://localhost:3000";
      impure-env = "GOPROXY=http://localhost:8888";

      download-buffer-size = "100000000";

      # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#set-up-the-remote-builder
      # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#optimise-the-remote-builder-configuration
      # https://nix.dev/manual/nix/2.23/command-ref/conf-file
      #trusted-users = [ "remotebuild" ]; # this moved to remote-builder.nix

      min-free = 10 * 1024 * 1024;
      max-free = 200 * 1024 * 1024;
      max-jobs = "auto";
      cores = 0;

      #nix.settings.experimental-features = [ "configurable-impure-env" ];
      #nix.settings.impure-env = "GOPROXY=http://localhost:3000";
    };

    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "weekly";                  # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };

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

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
    #ANOTHER_VARIABLE = "another-value";
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "libvirtd" "docker" "kubernetes" "video" ];
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

  # # https://nixos.wiki/wiki/SSH
  # # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/ssh/sshd.nix
  # # https://github.com/NixOS/nixpkgs/blob/47457869d5b12bdd72303d6d2ba4bfcc26fe8531/nixos/modules/services/security/sshguard.nix
  # services.openssh = {
  #   enable = true;
  #   openFirewall = true;
  #   settings = {
  #     # default key algos: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/ssh/sshd.nix#L546
  #     # KexAlgorithms = [
  #     #   "mlkem768x25519-sha256"
  #     #   "sntrup761x25519-sha512"
  #     #   "sntrup761x25519-sha512@openssh.com"
  #     #   "curve25519-sha256"
  #     #   "curve25519-sha256@libssh.org"
  #     #   "diffie-hellman-group-exchange-sha256"
  #     # ];
  #     Ciphers = [
  #       "chacha20-poly1305@openssh.com"
  #       "aes256-gcm@openssh.com"
  #       "aes128-gcm@openssh.com"
  #       # shortned default list
  #     ];
  #     Macs = [
  #       "hmac-sha2-512-etm@openssh.com"
  #       "hmac-sha2-256-etm@openssh.com"
  #       "umac-128-etm@openssh.com"
  #     ];
  #     # HostKeyAlgorithms = [
  #     #   "ssh-ed25519-cert-v01@openssh.com"
  #     #   "sk-ssh-ed25519-cert-v01@openssh.com"
  #     #   "rsa-sha2-512-cert-v01@openssh.com"
  #     #   "rsa-sha2-256-cert-v01@openssh.com"
  #     #   "ssh-ed25519"
  #     #   "sk-ssh-ed25519@openssh.com"
  #     #   "rsa-sha2-512"
  #     #   "rsa-sha2-256"
  #     # ];
  #     UsePAM = true;
  #     KbdInteractiveAuthentication = true;
  #     PermitRootLogin = "prohibit-password";
  #     PasswordAuthentication = false;
  #     ChallengeResponseAuthentication = false;
  #     X11Forwarding = false;
  #     GatewayPorts = "no";
  #   };
  # };

  # services.sshguard.enable = true;

  # search for serivces url
  #https://github.com/search?q=repo%3ANixOS%2Fnixpkgs+path%3A%2F%5Enixos%5C%2Fmodules%5C%2Fservices%5C%2F%2F+openssh&type=code

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  services.nix-serve = {
    enable = true;
    openFirewall = true;
    secretKeyFile = "/var/cache-priv-key.pem";
  };

  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

  # virtualisation.libvirtd.enable = true;
  # programs.virt-manager.enable = true;
  # services.qemuGuest.enable = true;

  nixpkgs.config = {
    allowUnfree = true;
    # permittedInsecurePackages = [
    #   "squid-6.10"
    # ];
  };
  # services.squid.enable = true;

  # https://wiki.nixos.org/wiki/Laptop
}
