#
# arm/pi-sebastian/nix/home-bob.nix
#
# Bob's home-manager config. Starts from the shared baseline in
# home-common.nix; add Bob-specific tweaks below.
#

{ config, pkgs, ... }:

{
  imports = [
    (import ./home-common.nix {
      username = "bob";
      gitName = "bob";
      gitEmail = "bob@example.com";
    })
  ];

  # --- Bob's personal config -------------------------------------------------
  # e.g. extra packages just for Bob, shell aliases, editor prefs:
  # home.packages = with pkgs; [ ];
  # programs.bash.shellAliases = { };
}
