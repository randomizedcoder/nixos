{ config, pkgs, ... }:

# Mirrors ~/nixos/hp/hp1/home.nix (the new mlx5-pair sibling). hp3 is
# the dut on the hp1↔hp3 testbed; otherwise its home-manager profile is
# identical to hp1's. Aligned with hp2/hp5 home profiles so all four
# benchmark hosts have the same userland toolchain.

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
    libgcc
    gcc
    automake
    gnumake
    pkg-config
    #
    perl
    python3
    #
    gawk
    jq
    git
    htop
    btop
    minicom
    #
    bzip2
    gzip
    lz4
    zip
    unzip
    xz
    zstd
    #
    rsync
    tree
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
    inetutils
    #
    inotify-tools
    #
    libcap
    gcc
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
