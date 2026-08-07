{
  config,
  pkgs,
  ...
}:

# Aligned with ~/nixos/hp/hp1/home.nix — chromebox1 is now an xdp2
# benchmark host, not a k3s control plane. Dropped KUBECONFIG and the
# kubectl shell alias.

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
    #
    strace
    #
    gnumake
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

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
}
