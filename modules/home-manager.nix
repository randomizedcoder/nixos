{ config, pkgs, ... }:

{
  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  home-manager.users.das = { pkgs, ... }: {
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
      #
      vlc
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
      gnome.gnome-settings-daemon
      gnome.gnome-disk-utility
      gnome.gnome-software
      gnome.gnome-tweaks
      gnome.simple-scan
      gnomeExtensions.appindicator
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

      libreoffice-qt
      hunspell
      hunspellDicts.en_AU
      #hunspellDicts.en_US
      gnomeExtensions.system-monitor
      # https://nixos.wiki/wiki/Firefox
      firefox
      # https://nixos.wiki/wiki/Chromium
      chromium
      # https://nixos.wiki/wiki/Slack
      slack
      #
      flameshot
      gimp-with-plugins
      #
      simplescreenrecorder
      #
      gedit
    ];

    # vscode
    # https://nixos.wiki/wiki/Visual_Studio_Code
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
        ms-vscode-remote.remote-containers
        ms-vscode-remote.remote-ssh
        #ms-vscode-remote.remote-ssh-edit
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
        serayuzgur.crates
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

    # https://heywoodlh.io/nixos-gnome-settings-and-keyboard-shortcuts
    dconf.settings = {
      "org/gnome/desktop/wm/preferences" = {
          button-layout = "close,minimize,maximize:appmenu";
      };
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
      "org/gnome/shell" = {
        favorite-apps = [
          "firefox.desktop"
          "code.desktop"
          "chromium.desktop"
          "alacritty.desktop"
        ];
        #disable-user-extensions = false;
      };
    };

    # https://nixos.wiki/wiki/Hyprland
    wayland.windowManager.hyprland = {
      # Whether to enable Hyprland wayland compositor
      enable = true;
      # The hyprland package to use
      package = pkgs.hyprland;
      # Whether to enable XWayland
      xwayland.enable = true;

      # Optional
      # Whether to enable hyprland-session.target on hyprland startup
      systemd.enable = true;
    };

    nixpkgs.config.allowUnfree = true;

    home.stateVersion = "23.11";
  };
}