#
# arm/pi-bob/nix/seed-config.nix
#
# Ship the config source ON the Pi so Bob can edit it and rebuild in place:
#   sudo nixos-rebuild switch --flake ~/pi-bob#pi-bob
#
# On first boot this drops a WRITABLE copy of this flake's own source into
# /home/bob/pi-bob (owned by bob). The copy happens only if the target does not
# already exist, so any edits Bob makes later survive future rebuilds - the
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
  # Bob should have the docs next to the config he's editing. Don't turn this
  # into an allow-list that could silently drop the README.
  configSrc = builtins.path {
    name = "pi-bob-config-src";
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
  system.activationScripts.seedBobConfig = {
    # Run after the `users` activation so /home/bob exists and bob is known.
    deps = [ "users" ];
    text = ''
      if [ ! -e /home/bob/pi-bob ]; then
        ${pkgs.coreutils}/bin/cp -r ${configSrc} /home/bob/pi-bob
        ${pkgs.coreutils}/bin/chown -R bob:users /home/bob/pi-bob
        ${pkgs.coreutils}/bin/chmod -R u+w /home/bob/pi-bob
      fi
    '';
  };
}
