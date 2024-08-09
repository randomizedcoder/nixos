{ config, pkgs, ... }:

# sudo cp ./nixos/modules/* /etc/nixos/
# sudo nixos-rebuild switch

{
  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  home-manager.users.das = { pkgs, ... }: {

    # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
    home.sessionVariables = {
        #GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
        # disable wayland
        #NIXOS_OZONE_WL = "1";
    };

    home.packages = with pkgs; [
      #
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
      #
      gawk
      jq
      git
      htop
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
      bpftools
      fping
      inetutils
      #
      hwloc
      bpftools
      #
      inotify-tools
      #
      neofetch
      #ffmpeg-full
      # go
      # https://nixos.wiki/wiki/Go
      # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
      # https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
      libcap
      gcc
      #  thunderbird
      go
      golangci-lint
      golangci-lint-langserver
      trunk-io
      buf
      buf-language-server
      #
      # debug
      strace
      #
      # rust
      # https://nixos.wiki/wiki/Rust
      pkgs.cargo
      pkgs.rustc
      #
      # https://nixos.wiki/wiki/Podman
      dive
      podman
      runc
      skopeo
      podman-tui
      podman-compose
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

    home.stateVersion = "24.05";
  };
}