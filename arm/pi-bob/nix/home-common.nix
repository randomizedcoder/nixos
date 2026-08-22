#
# arm/pi-bob/nix/home-common.nix
#
# Shared home-manager baseline, imported by each per-user module
# (home-bob.nix, home-sebastian.nix, home-das.nix). It is a function of the
# per-user parameters and returns a home-manager module, e.g.:
#   imports = [ (import ./home-common.nix {
#     username = "bob"; gitName = "bob"; gitEmail = "bob@example.com";
#   }) ];
#
# Per-user files add their own tweaks alongside that import, so bob and
# sebastian can diverge freely.
#
# Heavy CLI tooling lives system-wide in ./packages.nix, so this stays focused
# on per-user shell/editor/git configuration.
#

{
  username,
  gitName,
  gitEmail,
  # Optional per-user locale (LANG/LC_*) overrides, merged into the shell
  # environment. Defaults to {} (inherit the system en_US.UTF-8 locale). See
  # home-sebastian.nix for the Dutch wiring. The chosen locale must be
  # generated system-wide in nix/il8n.nix (i18n.supportedLocales).
  localeVars ? { },
}:

{ config, pkgs, ... }:

{
  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.sessionVariables = {
    TERM = "xterm-256color";
  } // localeVars;

  # Per-user packages (the bulk of the toolbox is system-wide in
  # nix/packages.nix; these are handy to also have in each user's profile).
  home.packages = with pkgs; [
    htop
    btop
  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  programs.vim = {
    enable = true;
    # Terminal-only vim. The default (vim-full) builds a GTK3/Wayland GUI that
    # needs wayland-scanner as a native tool and fails to cross-compile; this
    # is a headless CLI machine, so the plain build is what we want anyway.
    packageConfigurable = pkgs.vim;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = {
      ignorecase = true;
    };
    extraConfig = ''
      set mouse=a
    '';
  };

  programs.git = {
    enable = true;
    settings.user.email = gitEmail;
    settings.user.name = gitName;
    signing.format = null;
  };

  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
