{ config, pkgs, ... }:

{
  home.username = "das";
  home.homeDirectory = "/home/das";

  home.sessionVariables = {
    TERM = "xterm-256color";
  };

  home.packages = with pkgs; [
    # system / inspection
    killall
    lshw
    hwloc
    pciutils
    usbutils
    # multiplexers
    tmux
    screen
    # build
    gcc
    gnumake
    pkg-config
    python3
    # text / data
    gawk
    jq
    git
    htop
    btop
    minicom
    # compression
    gzip
    zstd
    xz
    zip
    unzip
    # transfer / files
    rsync
    tree
    # networking
    ethtool
    iproute2
    tcpdump
    fping
    inetutils
    netcat-gnu
    # debug
    strace
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
    settings.user.email = "dave.seddon.ca@gmail.com";
    settings.user.name = "randomizedcoder";
    signing.format = null;
  };

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
}
