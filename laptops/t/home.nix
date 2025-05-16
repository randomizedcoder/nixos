{
  hyprland,
  config,
  pkgs,
  overlay-unstable,
  ...
}:
#{ config, pkgs, ... }:
#{ config, inputs, pkgs, ... }:

# sudo cp ./nixos/modules/* /etc/nixos/
# sudo nixos-rebuild switch

{
  imports = [
    hyprland.homeManagerModules.default
    # other imports to go here
  ];

  home = {
    username = "das";
    homeDirectory = "/home/das";
  };

  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  #home-manager.users.das = { pkgs, ... }: {

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
  home.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = "1";

    QT_QPA_PLATFORM = "wayland";
    GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
    # disable wayland
    NIXOS_OZONE_WL = "1";
    GOPRIVATE = "gitlab.com/sidenio/*";
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
    gparted
    ncdu
    neofetch
    file

    # Terminal Multiplexers
    tmux
    screen

    # LLVM/Clang toolchain (needed for race detection and C/C++ builds)
    llvmPackages_19.libcxxClang
    llvmPackages_19.lld
    llvmPackages_19.libcxx.dev

    # Essential development libraries (minimal headers)
    glibc.dev
    stdenv.cc.cc.lib
    zlib.dev
    openssl.dev
    ncurses.dev
    libyaml.dev

    # Build Tools
    libgcc
    # https://nixos.wiki/wiki/C
    # https://search.nixos.org/packages?channel=24.05&show=gcc&from=0&size=50&sort=relevance&type=packages&query=gcc
    #gcc
    automake
    gnumake
    #cmake
    pkg-config

    # Scripting/Utils
    perl
    #3.12.8 on 12th of Feb 2025
    python3Full
    gawk
    jq
    git
    htop
    btop
    minicom

    bc

    # Compression
    bzip2
    gzip
    lz4
    zip
    unzip
    xz
    zstd

    gnutar

    # File Transfer/Management
    rsync
    tree

    # Terminals
    alacritty
    kitty
    #https://ghostty.org/
    ghostty

    # Networking
    ethtool
    iproute2
    vlan
    tcpdump
    wireshark
    unstable.iperf2
    netperf
    flent
    bpftools
    fping
    inetutils # Includes telnet
    netcat-gnu

    # Filesystem/Monitoring
    inotify-tools

    # Printing
    hplip
    #hplipWithPlugin

    # SDR
    gnuradio
    hackrf
    gqrx
    cubicsdr

    # Media
    vlc
    # ffmpeg moved to system package
    #ffmpeg_7-full
    #ffmpeg-full

    # Go Development
    # https://nixos.wiki/wiki/Go
    # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
    # https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
    libcap
    #gcc_multi
    #glibc_multi
    #  thunderbird
    #go_1_23
    unstable.go
    unstable.gopls
    unstable.golint
    golangci-lint
    unstable.golangci-lint-langserver
    # trunk is unfree, and i can't work out how to enable unfree
    #trunk-io
    # https://github.com/go-delve/delve
    unstable.delve
    # https://github.com/aarzilli/gdlv
    gdlv
    unstable.buf
    protobuf_27
    grpcurl
    # https://github.com/go-gorm/gen
    # https://github.com/infobloxopen/protoc-gen-gorm/blob/main/example/postgres_arrays/buf.gen.yaml
    gorm-gentool
    # removed 24.11
    #buf-language-server
    # https://tinygo.org/
    #tinygo

    # removing bazel and moving to the "nix develop" shell
    # # https://github.com/bazelbuild/bazel/tags
    # # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/tools/build-managers/bazel/bazel_7/default.nix#L524
    unstable.bazel_7
    unstable.bazel-buildtools

    unstable.code-cursor

    # # https://github.com/bazel-contrib/bazel-gazelle/tags
    # # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ba/bazel-gazelle/package.nix#L26
    # unstable.bazel-gazelle
    # unstable.bazel-buildtools
    # unstable.bazelisk
    # # https://github.com/buchgr/bazel-remote - maybe something to look at?
    # # https://github.com/buildfarm/buildfarm?tab=readme-ov-file#helm-chart

    # Debugging/Profiling
    graphviz # for pprof
    strace

    # Diffing
    meld

    # Editors
    helix

    # Rust Development
    # https://nixos.wiki/wiki/Rust
    cargo
    rustc
    rustfmt
    rust-analyzer
    clippy
    #clang_multi

    # Mobile Development
    flutter
    android-studio
    android-tools
    android-udev-rules

    # Gnome Related / Extensions
    # gnomeExtensions.emoji-copy
    # unstable.gnomeExtensions.workspace-switcher-manager
    gnome-extension-manager
    gnome-usage
    dconf-editor
    gnome-settings-daemon
    gnome-disk-utility
    gnome-software
    gnome-tweaks
    simple-scan
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

    # Office/Documents
    libreoffice-qt
    hunspell
    hunspellDicts.en_AU
    #hunspellDicts.en_US
    evince

    # Browsers
    # https://nixos.wiki/wiki/Firefox
    firefox
    # https://nixos.wiki/wiki/Chromium
    chromium
    #google-chrome
    # https://discourse.nixos.org/t/google-chrome-not-working-after-recent-nixos-rebuild/43746
    (google-chrome.override {
      commandLineArgs = [
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
      ];
    })

    # Communication
    # https://nixos.wiki/wiki/Slack
    unstable.slack
    unstable.zoom-us

    # Screenshots/Screen Recording
    # https://wiki.nixos.org/wiki/Flameshot
    (flameshot.override { enableWlrSupport = true; })
    grim # screenshot functionality
    slurp # screenshot functionality
    simplescreenrecorder
    # https://wiki.nixos.org/wiki/Gpu-screen-recorder
    gpu-screen-recorder # CLI
    gpu-screen-recorder-gtk # GUI

    # Graphics
    gimp-with-plugins

    # Text Editors
    gedit

    # Containers
    # https://nixos.wiki/wiki/Podman
    dive
    podman
    runc
    skopeo
    podman-tui
    podman-compose
    docker-buildx

    # Kubernetes
    #clickhouse
    #clickhouse-cli
    # https://github.com/int128/kubelogin
    kubelogin-oidc
    kubectl
    kubernetes-helm
    istioctl
    krew
    kubeshark
    kubectl-ktop
    kubectl-klock
    kube-capacity
    kubectl-images
    kubectl-gadget
    kdash
    # k9s --kubeconfig=dev-d.kubeconfig
    k9s

    # Misc
    # https://github.com/jrincayc/ucblogo-code
    ucblogo
    # https://github.com/wagoodman/dive
    # dive # Duplicate removed
    # https://github.com/sharkdp/hyperfine
    hyperfine

    # App Launchers
    rofi-wayland
    wofi

    # Raspberry Pi
    rpi-imager
  ];

  # vscode
  # https://nixos.wiki/wiki/Visual_Studio_Code
  # https://github.com/thexyno/nixos-config/blob/main/hm-modules/vscode/default.nix
  # nix run github:nix-community/nix-vscode-extensions# -- --list-extensions
  # https://mynixos.com/home-manager/options/programs.vscode
  programs.vscode = {
    enable = true;
    # package = pkgs.vscode;
    # extensions = with pkgs.vscode-extensions; [
    package = pkgs.unstable.vscode;
    extensions = with pkgs.unstable.vscode-extensions; [
      #bbenoist.nix
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
      ms-kubernetes-tools.vscode-kubernetes-tools
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
      #github.copilot
      # nix
      #brettm12345.nixfmt.vscode
      jnoortheen.nix-ide
      #jeff-hykin.better-nix-syntax
      rust-lang.rust-analyzer
      #bazel
      bazelbuild.vscode-bazel
    ];
  };

  #fonts.fonts = with pkgs; [
  #  nerdfonts
  #  meslo-lgs-nf
  #];

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

  # another example with dark colors:
  # https://github.com/HeinzDev/Hyprland-dotfiles/blob/main/home/home.nix#L70
  #
  # https://heywoodlh.io/nixos-gnome-settings-and-keyboard-shortcuts
  # https://rycee.gitlab.io/home-manager/options.xhtml#opt-dconf.settings
  dconf.settings = {
    "org/gnome/desktop/wm/preferences" = {
      #button-layout = "close,minimize,maximize,above:appmenu";
      button-layout = ":minimize,maximize,above,close";
      num-workspaces = 2;
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
      # toolkit-accessibility = true;
      toolkit-accessibility = false;
    };
    "org/gnome/shell" = {
      disable-user-extensions = false;
      favorite-apps = [
        "firefox.desktop"
        "google-chrome.desktop"
        "code.desktop"
        "chromium.desktop"
        "alacritty.desktop"
        #"kitty.desktop"
        "slack.desktop"
        "ghostty.desktop"
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

  # https://wiki.hyprland.org/Nix/Hyprland-on-Home-Manager/
  # wayland.windowManager.hyprland.enable = true; # enable Hyprland
  # Example: https://github.com/JaKooLit/NixOS-configs/blob/main/Ja-OS%20(configs%20using%20install%20script)/Asus-G15/hosts/G15-NixOS/config.nix#L144
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    #extraConfig = '' plugin = ${inputs.hy3.packages.${pkgs.system}.hy3}/lib/libhy3.so '';
    # plugins = [
    #   inputs.hyprland-plugins.packages.${pkgs.system}.hyprbars
    #   # ...
    #];
    extraConfig = ''
      # Monitor configuration (Example - replace with yours)
      monitor=,preferred,auto,1

      # Execute-once startup commands (Example)
      exec-once = waybar &
      exec-once = nm-applet --indicator

      # Keybindings (Example)
      bind = SUPER, Q, killactive,
      bind = SUPER, RETURN, exec, ${pkgs.alacritty}/bin/alacritty

      # Include other settings...
      # input { ... }
      # general { ... }
      # decoration { ... }
      # animations { ... }
      # etc...

      # Source other files if needed (less common with inline config)
      # source = ~/.config/hypr/myColors.conf
    '';
  };

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
  # https://mynixos.com/home-manager/options/programs.ghostty
  home.file.".config/ghostty/ghostty.toml" = {
    target = ".config/ghostty/ghostty.toml";
    text = ''
      [window]
      # Whether to show the scrollback sidebar.
      sidebar = true

      # The width of the scrollback sidebar.
      sidebar_width = 10

      # Whether to show the scrollback sidebar on the left or right.
      sidebar_position = "right"
    '';
  };
  # https://github.com/colemickens/nixcfg/blob/1915d408ea28a5b7279f94df7a982dbf2cf692ef/mixins/ghostty.nix#L19

  # set at flake.nix level
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [ overlay-unstable ];

  #home.stateVersion = "23.11";
  home.stateVersion = "24.11";
}
