# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./sysctl.nix
      ./locale.nix
      ./vm3.systemPackages.nix
      <home-manager/nixos>
      ./home-manager.nix
      # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix      <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
      #<nixpkgs/nixos/modules/profiles/qemu-guest.nix>
      #<nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # https://www.kernel.org/releases.html
  #boot.kernelPackages = pkgs.linuxPackages_4_19; # 4.19.319
  #boot.kernelPackages = pkgs.linuxPackages_5_4; # 5.4.281
  #boot.kernelPackages = pkgs.linuxPackages_5_15; # 5.15.164
  #boot.kernelPackages = pkgs.linuxPackages_6_1; # 6.1.103
  #boot.kernelPackages = pkgs.linuxPackages_6_8; # 6.8
  boot.kernelPackages = pkgs.linuxPackages_6_10; # 6.10

  # boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux_4_19.override {
  #   argsOverride = rec {
  #     src = pkgs.fetchurl {
  #           url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
  #           sha256 = "0ibayrvrnw2lw7si78vdqnr20mm1d3z0g6a0ykndvgn5vdax5x9a";
  #     };
  #     version = "4.19.60";
  #     modDirVersion = "4.19.60";
  #     };
  # });

  # nix = {
  #   gc = {
  #     automatic = true;                  # Enable automatic execution of the task
  #     dates = "weekly";                  # Schedule the task to run weekly
  #     options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
  #     randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
  #   };
  #   settings = {
  #     auto-optimise-store = true;
  #     experimental-features = [ "nix-command" "flakes" ];
  #   };
  # };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "vm3";

  # networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  users.users.root.initialHashedPassword = "$6$7KZXYg2OjRBy/KiC$T22ywYwqDQjqBTHXAnuVZ1Bl9a8osbttmRMpu2DHcRfR1BTl/Xza3WkSn7zij8pkPk5bye1u93gmJgTSeZgBY.";

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
    htop
  ];

  users.users.das = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    #initialPassword = "test";
    # mkpasswd -m sha-512
    initialHashedPassword = "$6$Cj2ptTRUdahPwOIP$ftQnDDtv.vppfuHFc0V7tsbG5w4wqR04GHRjFUJ48F9stu199iN69xwl/Sm9lGKG50Ieq4uzbA3g/tIEKj9UJ.";
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  services.timesyncd.enable = lib.mkDefault true;

  services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 22 ];
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # https://nixos.wiki/wiki/Docker
  # https://medium.com/thelinux/how-to-install-the-docker-in-nixos-with-simple-steps-226a7e9ef260
  virtualisation.docker.enable = true;
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
  virtualisation.docker.storageDriver = "btrfs";
  # https://www.qemu.org/docs/master/system/i386/microvm.html
  #imports = [ <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix> ];
  #virtualisation.qemu.options = [ "-M microvm,accel=kvm:tcg,acpi=on,mem-merge=on,pcie=on,pic=off,pit=off,usb=off" ];
  #virtualisation.qemu.options = [ "-M microvm,accel=kvm:tcg,acpi=on,mem-merge=on,pcie=on,pic=off,pit=off" ];


  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      diskSize = 8192;
    };
  };
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix#L240

  # virtualisation.forwardPorts = [
  #   { from = "host"; host.port = 8122; guest.port = 22; }
  #   #{ from = "host"; host.port = 8180; guest.port = 80; }
  # ];

  services.qemuGuest.enable = true;

  # https://releases.nixos.org/?prefix=nixos/
  system.stateVersion = "25.05";

}

