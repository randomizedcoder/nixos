{ config, pkgs, ... }:

# sudo cp ./nixos/modules/* /etc/nixos/
# sudo nixos-rebuild switch

{
  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  home-manager.users.das = { pkgs, ... }: {

    # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
    home.sessionVariables = {
    };

    home.packages = with pkgs; [
      #
      gparted
      hw-probe
      ncdu
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
      #iperf2
      netperf
      flent
      bpftools
      fping
      inetutils
      #
      hwloc
      bpftools
      #
      inotify-tools
      #
      #
      neofetch
      #
      # go
      # https://nixos.wiki/wiki/Go
      # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
      # https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
      libcap
      gcc
      #  thunderbird
      #
      # debug
      strace

    ];

    programs.bash.enable = true;

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

    # disable wayland
    # # https://nixos.wiki/wiki/Hyprland
    # # https://josiahalenbrown.substack.com/p/installing-nixos-with-hyprland
    # #programs.hyprland.enable = true;
    # wayland.windowManager.hyprland = {
    #   # Whether to enable Hyprland wayland compositor
    #   enable = true;
    #   # The hyprland package to use
    #   package = pkgs.hyprland;
    #   # Whether to enable XWayland
    #   xwayland.enable = true;

    #   # Optional
    #   # Whether to enable hyprland-session.target on hyprland startup
    #   systemd.enable = true;
    # };
    # # home.file.".config/hypr/hyprland.conf".text = ''
    # # '';


    home.file."containers.conf" = {
      target = ".config/containers/containers.conf";
      # https://docs.podman.io/en/v4.6.0/markdown/options/security-opt.html
      # https://github.com/containers/common/blob/main/docs/containers.conf.5.md
      text = ''
        [containers]
        annotations=["run.oci.keep_original_groups=1",]
        label=false
        #seccomp=unconfined
      '';
    };
    home.file."registries.conf" = {
      target = ".config/containers/registries.conf";
      text = ''
        [registries.search]
        registries = ['docker.io']
      '';
      # text = ''
      #   [registries.search]
      #   registries = ['docker.io', 'registry.gitlab.com']
      # '';
    };
    home.file."policy.json" = {
      target = ".config/containers/policy.json";
      text = ''
        {
            "default": [
                {
                    "type": "insecureAcceptAnything"
                }
            ],
            "transports":
                {
                    "docker-daemon":
                        {
                            "": [{"type":"insecureAcceptAnything"}]
                        }
                }
        }
      '';
    };

    nixpkgs.config.allowUnfree = true;

    home.stateVersion = "23.11";
  };
}