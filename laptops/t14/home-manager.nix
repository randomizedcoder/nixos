{ config, pkgs, ... }:

# sudo cp ./nixos/modules/* /etc/nixos/
# sudo nixos-rebuild switch

{
  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  home-manager.users.das = { pkgs, ... }: {

    # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
    home.sessionVariables = {
        GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
        # disable wayland
        #NIXOS_OZONE_WL = "1";
    };

    home.packages = with pkgs; [
      #
      killall
      hw-probe
      #
      gparted
      #
      ncdu
      #
      hw-probe
      lshw
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
      alacritty
      kitty
      #
      ethtool
      iproute2
      vlan
      tcpdump
      wireshark
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
      gnuradio
      hackrf
      gqrx
      cubicsdr
      #
      neofetch
      #
      vlc
      ffmpeg_7-full
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
      # https://github.com/go-delve/delve
      delve
      # https://github.com/aarzilli/gdlv
      gdlv
      buf
      buf-language-server
      #
      graphviz
      #
      meld
      #
      # https://nixos.wiki/wiki/Helix
      helix
      # rust
      # https://nixos.wiki/wiki/Rust
      pkgs.cargo
      pkgs.rustc
      #
      flutter
      android-studio
      android-tools
      android-udev-rules
      #
      # debug
      strace
      # Gnome related / extensions
      # gnomeExtensions.emoji-copy
      # unstable.gnomeExtensions.workspace-switcher-manager
      gnome-extension-manager
      gnome-usage
      gnome.dconf-editor
      #gnome.gnome-settings-daemon
      gnome-settings-daemon
      gnome.gnome-disk-utility
      gnome.gnome-software
      gnome.gnome-tweaks
      gnome.simple-scan
      gnomeExtensions.appindicator
      gnomeExtensions.settingscenter
      gnomeExtensions.system-monitor
      gnomeExtensions.dash-to-dock
      gnomeExtensions.just-perfection
      gnomeExtensions.logo-menu
      gnomeExtensions.wifi-qrcode
      gnomeExtensions.wireless-hid
      gnomeExtensions.user-themes
      gnomeExtensions.tray-icons-reloaded
      gnomeExtensions.vitals
      gnomeExtensions.dash-to-panel
      gnomeExtensions.sound-output-device-chooser
      gnomeExtensions.space-bar
      # https://github.com/AstraExt/astra-monitor
      gnomeExtensions.astra-monitor
      libgtop
      #
      libreoffice-qt
      hunspell
      hunspellDicts.en_AU
      #hunspellDicts.en_US
      #
      evince
      # https://nixos.wiki/wiki/Firefox
      firefox
      # https://nixos.wiki/wiki/Chromium
      chromium
      google-chrome
      # https://nixos.wiki/wiki/Slack
      slack
      #
      zoom-us
      #
      flameshot
      grim # screenshot functionality
      slurp # screenshot functionality
      #
      gimp-with-plugins
      #
      simplescreenrecorder
      #
      gedit
      #
      # https://nixos.wiki/wiki/Podman
      dive
      podman
      runc
      skopeo
      podman-tui
      podman-compose
      #
      rofi-wayland
      wofi
      #
      #clickhouse
      #clickhouse-cli
    ];

    # vscode
    # https://nixos.wiki/wiki/Visual_Studio_Code
    # nix run github:nix-community/nix-vscode-extensions# -- --list-extensions
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;
      extensions = with pkgs.vscode-extensions; [
        bbenoist.nix
        dart-code.dart-code
        dart-code.flutter
        golang.go
        hashicorp.terraform
        #k6.k6
        ms-azuretools.vscode-docker
        # https://github.com/orgs/microsoft/repositories?q=vscode
        ms-vscode-remote.remote-containers
        ms-vscode-remote.remote-ssh
        #ms-vscode-remote.remote-ssh-edit
        ms-vscode.makefile-tools
        ms-vscode.cmake-tools
        ms-vscode.cpptools
        #ms-vscode.cpptools-extension-pack
        #ms-vscode.cpptools-themes
        ms-vscode.hexeditor
        ms-vscode.makefile-tools
        ms-python.python
        ms-python.vscode-pylance
        #ms-vscode.remote-explorer
        #ms-vscode.remote-repositories
        #ms-vscode.remote-server
        redhat.vscode-yaml
        rust-lang.rust-analyzer
        #crates is depreciated
        #serayuzgur.crates
        tamasfe.even-better-toml
        timonwong.shellcheck
        #trunk.io
        zxh404.vscode-proto3
        yzhang.markdown-all-in-one
        #platformio.platformio-ide
        github.copilot
        # nix
        #brettm12345.nixfmt.vscode
        jnoortheen.nix-ide
        #jeff-hykin.better-nix-syntax
      ];
    };

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

    # https://nixos.wiki/wiki/OBS_Studio
    # TODO add kernel module for virtual camera
    programs.obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-backgroundremoval
        obs-pipewire-audio-capture
      ];
    };

    # https://heywoodlh.io/nixos-gnome-settings-and-keyboard-shortcuts
    dconf.settings = {
      "org/gnome/desktop/wm/preferences" = {
          button-layout = "close,minimize,maximize:appmenu";
      };
      # "org/gnome/desktop/interface" = {
      #   color-scheme = "prefer-dark";
      # };
      "org/gnome/desktop/interface" = {
        clock-show-seconds = true;
        clock-show-weekday = true;
        color-scheme = "prefer-dark";
        enable-hot-corners = false;
        font-antialiasing = "grayscale";
        font-hinting = "slight";
        gtk-theme = "Nordic";
        toolkit-accessibility = true;
      };
      "org/gnome/shell" = {
        disable-user-extensions = false;
        favorite-apps = [
          "firefox.desktop"
          "google-chrome-stable.desktop"
          "code.desktop"
          "chromium.desktop"
          "alacritty.desktop"
          "kitty.desktop"
          "slack.desktop"
        ];
      enabled-extensions = with pkgs.gnomeExtensions; [
        blur-my-shell.extensionUuid
        gsconnect.extensionUuid
      ];
      };
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

    services.flameshot = {
      enable = true;
      settings.General = {
        showStartupLaunchMessage = false;
        saveLastRegion = true;
      };
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

    home.stateVersion = "23.11";
  };
}
