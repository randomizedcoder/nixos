{ config, pkgs, ... }:

# sudo cp ./nixos/modules/* /etc/nixos/
# sudo nixos-rebuild switch

{
  home.username = "das";
  home.homeDirectory = "/home/das";

  imports = [
    ./ffmpeg_systemd_service.nix
  ];

  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  #home-manager.users.das = { pkgs, ... }: {

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
  home.sessionVariables = {
      #GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
      # disable wayland
      #NIXOS_OZONE_WL = "1";
      KUBECONFIG = "/home/das/k3s.yaml";
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
    # https://search.nixos.org/packages?channel=24.05&show=gcc&from=0&size=50&sort=relevance&type=packages&query=gcc
    gcc
    automake
    gnumake
    #cmake
    pkg-config
    #
    # alsa-lib
    # alsa-lib-with-plugins
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
    #wireshark
    #iperf2
    netperf
    flent
    bpftools
    fping
    inetutils
    #
    netcat-gnu
    # for telnet
    inetutils
    #
    hwloc
    bpftools
    #
    inotify-tools
    #
    libcap
    gcc
    #  thunderbird
    go
    # rust
    # https://nixos.wiki/wiki/Rust
    # pkgs.cargo
    # pkgs.rustc
    #
    # debug
    strace
    #
    dive
    # for pprof
    graphviz
    #
    #ffmpeg
    #ffmpeg-full
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
    userName = "randomizedcoder ";
    #signing.key = "GPG-KEY-ID";
    #signing.signByDefault = true;
  };

  nixpkgs.config.allowUnfree = true;

  programs.home-manager.enable = true;
  home.stateVersion = "24.11";
  #};
}
