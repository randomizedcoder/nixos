{
  config,
  pkgs,
  ...
}:

{

  home = {
    username = "das";
    homeDirectory = "/home/das";
  };

  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  #home-manager.users.das = { pkgs, ... }: {

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
  home.sessionVariables = {

    TERM = "xterm-256color";

    #HTTP_PROXY = "http://hp4.home:3128";
    #HTTPS_PROXY = "http://hp4.home:3128";
    #NO_PROXY = "localhost,127.0.0.1,::1,172.16.0.0/16";
    # You can also use ALL_PROXY or FTP_PROXY if needed
    # ALL_PROXY = "http://hp4:3128";
  };

  home.packages = with pkgs; [
    # System/Info Tools
    killall
    hw-probe
    lshw
    hwloc
    #gparted
    ncdu
    neofetch
    file

    # Terminal Multiplexers
    tmux
    screen

    # # Essential development libraries (minimal headers)
    # glibc.dev
    # stdenv.cc.cc.lib
    # zlib.dev
    # openssl.dev
    # ncurses.dev
    # libyaml.dev

    # Build Tools
    libgcc
    # https://nixos.wiki/wiki/C
    # https://search.nixos.org/packages?channel=24.05&show=gcc&from=0&size=50&sort=relevance&type=packages&query=gcc
    gcc
    automake
    gnumake
    gnumake42
    # cmake
    pkg-config

    # # Scripting/Utils
    # perl
    # #3.12.8 on 12th of Feb 2025
    # python3Full
    # gawk
    # jq

    git
    htop
    btop
    minicom

    # bc

    # # Compression
    bzip2
    gzip
    lz4
    zip
    unzip
    xz
    zstd

    #gnutar

    # File Transfer/Management
    rsync
    tree

    # # Terminals
    # alacritty
    # kitty
    # #https://ghostty.org/
    # ghostty

    # Networking
    ethtool
    iproute2
    vlan
    tcpdump
    wireshark
    iperf2
    netperf
    flent
    bpftools
    fping
    inetutils # Includes telnet
    netcat-gnu

    # Filesystem/Monitoring
    inotify-tools

    #silly
    cmatrix
    sl

  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      k = "kubectl";
    };
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
    '';
  };
  #ldflags = [
  #  "-X main.Version=${version}"
  #  "-X main.Commit=${version}"
  #];

  programs.git = {
    enable = true;
    userEmail = "dave.seddon.ca@gmail.com";
    userName = "randomizedcoder";
    #signing.key = "GPG-KEY-ID";
    #signing.signByDefault = true;
  };

  nixpkgs.config.allowUnfree = true;

  #home.stateVersion = "24.11";
  home.stateVersion = "25.05";
}
