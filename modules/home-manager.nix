{ config, pkgs, ... }:

{
  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  home-manager.users.das = { pkgs, ... }: {
    home.packages = with pkgs; [
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
      pkg-config
      #
      perl
      python3
      #
      gawk
      jq
      git
      htop
      minicom
      #
      ethtool
      iproute2
      vlan
      tcpdump
      wireshark
      iperf2
      netperf
      flent
      bpftools
      #
      hwloc
      # go
      # https://nixos.wiki/wiki/Go
      # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
      # https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
      libcap
      gcc
      #  thunderbird
      go
      # rust
      # https://nixos.wiki/wiki/Rust
      pkgs.cargo
      pkgs.rustc
    ];

    programs.bash.enable = true;
    home.stateVersion = "23.11";

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
  };
}