{ config, pkgs, ... }:

# Aligned with ~/nixos/hp/hp1/home.nix — t is now an xdp2 benchmark
# host, not a Hyprland workstation. Dropped all the desktop / dotfile /
# editor-specific config that was in the prior multi-thousand-line
# home.nix. The historic file is preserved in git history if anyone
# needs to restore the laptop's desktop config.

{
  home.username = "das";
  home.homeDirectory = "/home/das";

  home.sessionVariables = {
      TERM = "xterm-256color";
  };

  home.packages = with pkgs; [
    killall
    hw-probe
    lshw
    hwloc
    #
    tmux
    screen
    #
    gawk
    jq
    git
    htop
    btop
    #
    rsync
    #
    ethtool
    iproute2
    vlan
    tcpdump
    netperf
    flent
    bpftools
    fping
    inetutils
    #
    netcat-gnu
    #
    inotify-tools
    #
    libcap
    gcc
    automake
    gnumake
    pkg-config
    perl
    python3
    #
    go
    #
    strace
    #
    dive
    graphviz
    #
    iftop
  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
    '';
  };

  programs.git = {
    enable = true;
    userEmail = "dave.seddon.ca@gmail.com";
    userName = "randomizedcoder ";
  };

  nixpkgs.config.allowUnfree = true;

  programs.home-manager.enable = true;
  home.stateVersion = "24.11";
}
