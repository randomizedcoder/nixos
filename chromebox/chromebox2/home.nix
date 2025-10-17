{
  config,
  pkgs,
  ...
}:
{
  home.username = "das";
  home.homeDirectory = "/home/das";

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
    #
    # debug
    strace
    #
    gnumake
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

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
}
