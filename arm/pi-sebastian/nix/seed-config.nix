#
# arm/pi-sebastian/nix/seed-config.nix
#
# Ship the config source ON the Pi so Sebastian can edit it and rebuild in place:
#   sudo nixos-rebuild switch --flake ~/pi-sebastian#pi-sebastian
#
# On first boot this drops a WRITABLE copy of this flake's own source into
# /home/sebastian/pi-sebastian (owned by sebastian). The copy happens only if the
# target does not already exist, so any edits Sebastian makes later survive future rebuilds - the
# activation script never clobbers them. The pristine source also stays in the
# Nix store read-only (`self`), so a fresh copy is always recoverable.
#
# `self` is the flake itself, made available to modules via `specialArgs =
# inputs` in flake.nix.
#
{ self, pkgs, lib, ... }:

let
  # The flake source copied into the store under a stable name. This is an
  # exclude-list (drop only the VCS dir and build symlinks), so EVERYTHING else
  # ships to the Pi - including README.md and all the docs, which is deliberate:
  # Sebastian should have the docs next to the config he's editing. Don't turn this
  # into an allow-list that could silently drop the README.
  configSrc = builtins.path {
    name = "pi-sebastian-config-src";
    path = self.outPath;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      base != ".git" && base != "result" && !(lib.hasPrefix "result" base);
  };
in
{
  system.activationScripts.seedSebastianConfig = {
    # Run after the `users` activation so /home/sebastian exists and sebastian is known.
    deps = [ "users" ];
    text = ''
      if [ ! -e /home/sebastian/pi-sebastian ]; then
        ${pkgs.coreutils}/bin/cp -r ${configSrc} /home/sebastian/pi-sebastian
        ${pkgs.coreutils}/bin/chown -R sebastian:users /home/sebastian/pi-sebastian
        ${pkgs.coreutils}/bin/chmod -R u+w /home/sebastian/pi-sebastian
      fi
    '';
  };
}
