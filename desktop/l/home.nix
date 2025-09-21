{
  #hyprland,
  config,
  pkgs,
  ...
}:

{
  # Ghostty configuration
  programs.ghostty = {
    enable = true;
    # settings = {
    # settings doesn't work
  };
  # https://ghostty.zerebos.com/app/import-export
  # no scorllback limit
  # https://github.com/ghostty-org/ghostty/issues/111
  xdg.configFile."ghostty/config.toml".text = ''
    term = xterm-256color
    scrollback-limit = 10000001
    image-storage-limit = 320000001
    clipboard-write = allow
    window-subtitle = working-directory
    background-opacity = 0.91
    background-blur = 20
  '';

  home = {
    username = "das";
    homeDirectory = "/home/das";
  };

  # https://nix-community.github.io/home-manager/index.xhtml#ch-installation
  #home-manager.users.das = { pkgs, ... }: {

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
  home.sessionVariables = {
    #NIXPKGS_ALLOW_UNFREE = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";

    QT_QPA_PLATFORM = "wayland";
    # GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
    # disable wayland
    # NIXOS_OZONE_WL = "1";
    GOPRIVATE = "gitlab.com/sidenio/*";
    TERM = "xterm-256color";

    #HIP_VISIBLE_DEVICES=0

    #HTTP_PROXY = "http://hp4.home:3128";
    #HTTPS_PROXY = "http://hp4.home:3128";
    #NO_PROXY = "localhost,127.0.0.1,::1,172.16.0.0/16";
    # You can also use ALL_PROXY or FTP_PROXY if needed
    # ALL_PROXY = "http://hp4:3128";

    # Flutter development environment variables
    JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
    #CHROME_EXECUTABLE = "/etc/profiles/per-user/das/bin/google-chrome-stable";
    CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome-stable";
    GOOGLE_APPLICATION_CREDENTIALS="~/Downloads/dashboard-dev-3da32-83d127a0f9ba.json";
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

    # # Hyprland related
    # waybar
    # swaybg
    # swaylock
    # wl-clipboard
    # wf-recorder
    # grimblast
    # hyprpaper
    # hyprpicker
    # hypridle
    # hyprlock

    # Terminal Multiplexers
    tmux
    screen

    # # LLVM/Clang toolchain (needed for race detection and C/C++ builds)
    # llvmPackages_20.clang-tools
    # llvmPackages_20.lld

    # # LLVM C++ Standard Library, compiler runtime, and unwind library
    # #llvmPackages_20.stdenv
    # llvmPackages_20.libcxxStdenv
    # llvmPackages_20.libcxxClang
    # llvmPackages_20.libcxx          # Provides libc++.so, libc++.a (libraries)
    # llvmPackages_20.libcxx.dev      # Provides C++ headers
    # # do NOT include llvm.libc-full, because it will override glibc
    # #llvm.libc-full
    # llvmPackages_20.compiler-rt     # Provides libclang_rt.builtins*.a
    # llvmPackages_20.compiler-rt.dev # Provides libclang_rt headers
    # llvmPackages_20.libunwind       # Provides libunwind for exception handling
    # llvmPackages_20.libunwind.dev   # Provides libunwind headers

    # llvmPackages_20.libclang llvmPackages_20.libclang.dev llvmPackages_20.libclang.lib

    # Essential development libraries (minimal headers)
    glibc glibc.dev glibc.static
    libgcc libgcc.lib
    gcc-unwrapped gcc-unwrapped.lib gcc-unwrapped.libgcc
    stdenv.cc.cc.lib
    zlib.dev
    openssl openssl.dev openssl.out
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

    gdb

    # Scripting/Utils
    perl
    python313
    gawk
    jq
    git
    htop
    # using btop-romc
    #btop
    below
    minicom

    bc

    # Compression
    bzip2
    gzip
    lz4
    zip
    unzip
    #xz
    #zstd

    gnutar

    # File Transfer/Management
    rsync
    tree

    nixpkgs-fmt

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
    iperf2
    netperf
    flent
    bpftools
    fping
    inetutils # Includes telnet
    netcat-gnu
    net-tools # for netstat

    # Filesystem/Monitoring
    inotify-tools

    # SDR
    gnuradio
    hackrf
    gqrx
    cubicsdr

    # Media
    vlc
    # ffmpeg moved to system package
    ffmpeg_7-full

    # Go Development
    # https://nixos.wiki/wiki/Go
    # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
    # https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
    libcap
    #gcc_multi
    #glibc_multi
    #  thunderbird
    #go_1_23
    go
    gopls
    golint
    golangci-lint
    golangci-lint-langserver
    # trunk is unfree, and i can't work out how to enable unfree
    #trunk-io
    # https://github.com/go-delve/delve
    delve
    # https://github.com/aarzilli/gdlv
    gdlv
    buf
    #protobuf_27
    #grpcurl
    # https://github.com/go-gorm/gen
    # https://github.com/infobloxopen/protoc-gen-gorm/blob/main/example/postgres_arrays/buf.gen.yaml
    #gorm-gentool
    # removed 24.11
    #buf-language-server
    # https://tinygo.org/
    #tinygo

    # removing bazel and moving to the "nix develop" shell
    # # https://github.com/bazelbuild/bazel/tags
    # # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/tools/build-managers/bazel/bazel_7/default.nix#L524
    #bazel_7
    bazel-buildtools
    bazelisk

    code-cursor

    # # https://github.com/bazel-contrib/bazel-gazelle/tags
    # # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ba/bazel-gazelle/package.nix#L26
    # bazel-gazelle
    # bazel-buildtools
    # bazelisk
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
    flutter #3.35.2
    #flutter329
    # https://search.nixos.org/packages?channel=unstable&query=flutter
    firebase-tools
    android-studio
    android-tools
    android-udev-rules
    # Java for Android development
    jdk17

    nordic
    gnome-themes-extra
    #gnome-shell-extensions

    # Gnome Related / Extensions
    # gnomeExtensions.emoji-copy
    # gnomeExtensions.workspace-switcher-manager
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
    gnomeExtensions.obs-status
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
    slack
    zoom-us

    # Screenshots/Screen Recording
    # https://wiki.nixos.org/wiki/Flameshot
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
    rofi
    wofi

    # Raspberry Pi
    #rpi-imager

    #silly
    cmatrix
    sl
    vectoroids # game
    # https://feralinteractive.github.io/gamemode/
    # sameboy
    # https://github.com/dreamchess/dreamchess
    chessx
    chessdb
    gnuchess
    dreamchess
    xboard
    fairymax # required by xboard
    stockfish # for xboard
    #pychess
    gnome-chess
    arena
    # Audio utilities for chess applications (xboard uses aplay for sound effects)
    alsa-utils

    # https://github.com/ccMSC/glava
    # glava
    # gzdoom needs .wad files
    # https://github.com/colemickens/gzdoom
    # gzdoom

    # https://github.com/sonald/blur-effect
    # blur-effect

    #gpu monitoring
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    rocmPackages.rocm-core
    rocmPackages.rocmPath
    lact
    # https://github.com/aristocratos/btop
    btop-rocm

    # https://github.com/ollama/ollama
    ollama-rocm
    rocmPackages.rccl
    # https://jeffser.com/alpaca/
    alpaca

    # virtual camera control
    # v4l2-ctl --list-devices
    v4l-utils
    kdePackages.kdenlive

    flightgear
    linuxConsoleTools #jscal https://wiki.flightgear.org/Input_device

    i2c-tools # sudo i2cdetect -l
    #liquidctl # moved to systemPackages.nix

    # Screenshot tool with Wayland support
    (flameshot.override { enableWlrSupport = true; })

    # Custom onnxruntime package
    onnxruntime

    # Custom Python onnxruntime module
    python313Packages.onnxruntime
  ];

  # vscode
  # https://nixos.wiki/wiki/Visual_Studio_Code
  # https://github.com/thexyno/nixos-config/blob/main/hm-modules/vscode/default.nix
  # nix run github:nix-community/nix-vscode-extensions# -- --list-extensions
  # https://mynixos.com/home-manager/options/programs.vscode
  # https://search.nixos.org/packages?channel=unstable&query=vscode-extensions
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      golang.go
      dart-code.dart-code
      dart-code.flutter
      hashicorp.terraform
      ms-azuretools.vscode-docker
      ms-vscode-remote.remote-containers
      ms-vscode-remote.remote-ssh
      ms-vscode.makefile-tools
      ms-vscode.cmake-tools
      ms-vscode.cpptools
      ms-vscode.hexeditor
      ms-vscode.makefile-tools
      ms-python.python
      ms-python.vscode-pylance
      ms-kubernetes-tools.vscode-kubernetes-tools
      redhat.vscode-yaml
      rust-lang.rust-analyzer
      tamasfe.even-better-toml
      timonwong.shellcheck
      zxh404.vscode-proto3
      yzhang.markdown-all-in-one
      jnoortheen.nix-ide
      rust-lang.rust-analyzer
      bazelbuild.vscode-bazel
      continue.continue
      rooveterinaryinc.roo-cline
      waderyan.gitblame
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
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/programs/obs-studio.nix
  programs.obs-studio = {
    enable = true;
    # virtual camera is not a home manager option, and we have v4l2loopback enabled in extraModprobeConfig
    #enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-3d-effect
      wlrobs
      #obs-vnc
      obs-ndi
      waveform
      pixel-art
      obs-vaapi
      obs-noise
      obs-teleport
      obs-markdown
      #obs-webkitgtk # seems to be removed
      obs-gstreamer
      input-overlay
      obs-rgb-levels
      obs-mute-filter
      obs-source-clone
      obs-shaderfilter
      obs-source-record
      obs-retro-effects
      obs-replay-source
      obs-freeze-filter
      obs-color-monitor
      #looking-glass-obs
      obs-vintage-filter
      obs-scale-to-sound
      obs-media-controls
      obs-composite-blur
      obs-advanced-masks
      #obs-vertical-canvas # not sure what this is, but it flickered
      obs-source-switcher
      obs-move-transition
      obs-gradient-source
      #obs-dvd-screensaver
      #obs-dir-watch-media
      obs-transition-table
      obs-recursion-effect
      obs-backgroundremoval # https://github.com/royshil/obs-backgroundremoval
      obs-stroke-glow-shadow
      obs-scene-as-transition
      obs-browser-transition
      advanced-scene-switcher
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
      icon-theme = "Papirus-Dark";
      cursor-theme = "Adwaita";
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
    # "org/gnome/shell/extensions/user-theme" = {
    #   name = "Nordic";
    # };
    enabled-extensions = with pkgs.gnomeExtensions; [
      blur-my-shell.extensionUuid
      gsconnect.extensionUuid
    ];
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
  # https://github.com/colemickens/nixcfg/blob/1915d408ea28a5b7279f94df7a982dbf2cf692ef/mixins/ghostty.nix#L19

  # nixpkgs.config.allowUnfree is set at flake.nix level

  home.stateVersion = "24.11";
}
