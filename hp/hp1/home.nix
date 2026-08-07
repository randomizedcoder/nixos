{ config, pkgs, ... }:

# Aligned with ~/nixos/hp/hp2/home.nix — this hp1 box is now a dedicated
# xdp2 benchmark host (mlx5 pair with hp3), not a k3s/satellite-emulation
# rig. Trimmed the k3s/kube aliases and KUBECONFIG env var the legacy
# config carried.

{
  home.username = "das";
  home.homeDirectory = "/home/das";

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
  home.sessionVariables = {
      TERM = "xterm-256color";
  };

  home.packages = with pkgs; [
    #
    killall
    hw-probe
    lshw
    hwloc
    #
    tmux
    screen
    #
    libgcc
    # https://nixos.wiki/wiki/C
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
