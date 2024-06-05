{ config, pkgs, ... }:

{
  # https://github.com/NixOS/nixpkgs/blob/095f1acb70302bd74cd5f3ab02a64bdfac36daa8/nixos/modules/system/boot/systemd.nix#L534
  # https://discourse.nixos.org/t/overriding-modifying-systemd-unit-file/45621/7

  # https://mynixos.com/nixpkgs/options/systemd
  systemd.extraConfig = "CPUAffinity=4-7";

  #https://mynixos.com/options/systemd.user
  systemd.user.extraConfig = "CPUAffinity=4-7";
  # create your own service
  # https://discourse.nixos.org/t/how-to-use-toplevel-overrides-for-systemd/12501
}