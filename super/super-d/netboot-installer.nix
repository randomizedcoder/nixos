#
# ~/nixos/super/super-d/netboot-installer.nix
#
# The shared PXE netboot INSTALLER image, built inline by this node's flake.nix
# and served by pxe.nix over HTTP/TFTP (anycast). ONE image for every node:
# a single untagged eno1 on the provisioning VLAN 402 via DHCP (no bond, no
# VLAN 401 — the *installed* system configures those). Brings sshd + the das root
# key + storcli/zfs/disko so `nixos-anywhere` can drive the install from super-d.
#
# Self-contained (no external file deps) so it travels with the node dir on
# `make sync`. Mirrors installer/flake.nix's netboot variant; keep them in step.
#
{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];

  networking.hostName = "super-netboot";
  networking.hostId = "0e5eb007";                 # installer only (no installed pool)
  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;      # untagged → provisioning VLAN 402
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # kernel + stage-1 on local VGA (tty0) AND the Supermicro SOL (ttyS1/COM2).
  boot.kernelParams = [ "console=tty0" "console=ttyS1,115200n8" ];
  boot.kernelModules = [ "ixgbe" ];

  documentation.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.enableAllFirmware = lib.mkForce false;

  # root SSH (for nixos-anywhere / manual install from super-d).
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
  ];

  # Storage build + install tools (storcli is unfree).
  boot.supportedFilesystems = [ "zfs" ];
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [ storcli gptfdisk util-linux zfs disko ];

  system.stateVersion = "26.05";
}
