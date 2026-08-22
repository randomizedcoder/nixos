#
# arm/pi-sebastian/nix/home-sebastian.nix
#
# Sebastian's home-manager config. Starts from the shared baseline in
# home-common.nix; add Sebastian-specific tweaks below.
#
# Sebastian is German, so his shell uses the Germany locale (language +
# date/number/paper/measurement formatting). The de_DE.UTF-8 locale is
# generated system-wide in nix/il8n.nix.
#

{ config, pkgs, ... }:

{
  imports = [
    (import ./home-common.nix {
      username = "sebastian";
      gitName = "sebastian";
      gitEmail = "sebastian@example.com";
      localeVars = {
        LANG = "de_DE.UTF-8";
        LC_ADDRESS = "de_DE.UTF-8";
        LC_IDENTIFICATION = "de_DE.UTF-8";
        LC_MEASUREMENT = "de_DE.UTF-8";
        LC_MONETARY = "de_DE.UTF-8";
        LC_NAME = "de_DE.UTF-8";
        LC_NUMERIC = "de_DE.UTF-8";
        LC_PAPER = "de_DE.UTF-8";
        LC_TELEPHONE = "de_DE.UTF-8";
        LC_TIME = "de_DE.UTF-8";
      };
    })
  ];

  # --- Sebastian's personal config -------------------------------------------
  # home.packages = with pkgs; [ ];
  # programs.bash.shellAliases = { };
}
