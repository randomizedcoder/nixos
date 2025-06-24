{
  hyprland,
  config,
  pkgs,
  ...
}:

{
  imports = [
    hyprland.homeManagerModules.default
  ];

  # Hyprland window manager configuration
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    extraConfig = ''
      # Monitor configuration
      monitor=,preferred,auto,1

      # Execute-once startup commands
      exec-once = waybar
      exec-once = swaybg -i ~/.config/hypr/wallpaper.jpg
      exec-once = hypridle
      exec-once = wl-paste --type text --watch cliphist store
      exec-once = wl-paste --type image --watch cliphist store

      # Input configuration
      input {
        kb_layout = us
        kb_variant =
        kb_model =
        kb_options =
        kb_rules =

        follow_mouse = 1
        touchpad {
          natural_scroll = true
          scroll_factor = 0.3
        }
        sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
      }

      # General settings
      general {
        gaps_in = 5
        gaps_out = 10
        border_size = 2
        col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        col.inactive_border = rgba(595959aa)
        layout = dwindle
        no_cursor_warps = true
      }

      # Decoration settings
      decoration {
        rounding = 10
        blur {
          enabled = true
          size = 3
          passes = 1
        }
        drop_shadow = true
        shadow_range = 4
        shadow_render_power = 3
        col.shadow = rgba(1a1a1aee)
      }

      # Animation settings
      animations {
        enabled = true
        bezier = myBezier, 0.05, 0.9, 0.1, 1.05
        animation = windows, 1, 7, myBezier
        animation = windowsOut, 1, 7, default, popin 80%
        animation = border, 1, 10, default
        animation = borderangle, 1, 8, default
        animation = fade, 1, 7, default
        animation = workspaces, 1, 6, default
      }

      # Layout settings
      dwindle {
        pseudotile = true
        preserve_split = true
      }

      # Gesture settings
      gestures {
        workspace_swipe = true
        workspace_swipe_fingers = 3
      }

      # Keybindings
      bind = SUPER, Q, killactive,
      bind = SUPER, RETURN, exec, ${pkgs.alacritty}/bin/alacritty
      bind = SUPER, D, exec, wofi --show drun
      bind = SUPER, F, fullscreen
      bind = SUPER, H, movefocus, l
      bind = SUPER, L, movefocus, r
      bind = SUPER, K, movefocus, u
      bind = SUPER, J, movefocus, d
      bind = SUPER, left, movewindow, l
      bind = SUPER, right, movewindow, r
      bind = SUPER, up, movewindow, u
      bind = SUPER, down, movewindow, d
      bind = SUPER SHIFT, H, movewindow, l
      bind = SUPER SHIFT, L, movewindow, r
      bind = SUPER SHIFT, K, movewindow, u
      bind = SUPER SHIFT, J, movewindow, d
      bind = SUPER, 1, workspace, 1
      bind = SUPER, 2, workspace, 2
      bind = SUPER, 3, workspace, 3
      bind = SUPER, 4, workspace, 4
      bind = SUPER, 5, workspace, 5
      bind = SUPER, 6, workspace, 6
      bind = SUPER, 7, workspace, 7
      bind = SUPER, 8, workspace, 8
      bind = SUPER, 9, workspace, 9
      bind = SUPER, 0, workspace, 10
      bind = SUPER SHIFT, 1, movetoworkspace, 1
      bind = SUPER SHIFT, 2, movetoworkspace, 2
      bind = SUPER SHIFT, 3, movetoworkspace, 3
      bind = SUPER SHIFT, 4, movetoworkspace, 4
      bind = SUPER SHIFT, 5, movetoworkspace, 5
      bind = SUPER SHIFT, 6, movetoworkspace, 6
      bind = SUPER SHIFT, 7, movetoworkspace, 7
      bind = SUPER SHIFT, 8, movetoworkspace, 8
      bind = SUPER SHIFT, 9, movetoworkspace, 9
      bind = SUPER SHIFT, 0, movetoworkspace, 10
      bind = SUPER, mouse_down, workspace, e+1
      bind = SUPER, mouse_up, workspace, e-1
      bind = SUPER, period, togglespecialworkspace, magic
      bind = SUPER SHIFT, period, movetoworkspace, special:magic
      bind = SUPER, S, togglesplit,
      bind = SUPER, P, pseudo,
      bind = SUPER, V, togglefloating,
      bind = SUPER, R, exec, wofi --show run
      bind = SUPER, Print, exec, grimblast --notify copysave area
      bind = SUPER SHIFT, Print, exec, grimblast --notify copysave screen
      bind = SUPER, X, exec, wl-clipboard-manager
      bind = SUPER, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy
    '';
  };

  # Waybar configuration
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        spacing = 4;
        modules-left = [
          "hyprland/workspaces"
          "hyprland/submap"
        ];
        modules-center = [
          "hyprland/window"
        ];
        modules-right = [
          "pulseaudio"
          "network"
          "cpu"
          "memory"
          "battery"
          "clock"
        ];
        "hyprland/workspaces" = {
          format = "{name}";
          on-click = "activate";
          sort-by-number = true;
        };
        "hyprland/window" = {
          format = "{}";
          separate-outputs = true;
        };
        "pulseaudio" = {
          format = "{icon} {volume}%";
          format-muted = "🔇";
          format-icons = {
            headphone = "🎧";
            handsfree = "📱";
            headset = "🎧";
            phone = "☎️";
            portable = "📱";
            car = "🚗";
            default = ["🔈" "🔉" "🔊"];
          };
          on-click = "pavucontrol";
        };
        "network" = {
          format-wifi = "📶 {essid}";
          format-ethernet = "🌐 {ipaddr}/{cidr}";
          format-linked = "🌐 {ifname} (No IP)";
          format-disconnected = "⚠️ Disconnected";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
        };
        "cpu" = {
          format = "🖥️ {usage}%";
          tooltip-format = "{usage}% used";
        };
        "memory" = {
          format = "🧠 {percentage}%";
          tooltip-format = "{used:0.1f}GB/{total:0.1f}GB used";
        };
        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "⚡ {capacity}%";
          format-plugged = "🔌 {capacity}%";
          format-icons = ["🔋" "🔋" "🔋" "🔋" "🔋"];
        };
        "clock" = {
          format = "🕒 {:%H:%M}";
          format-alt = "🕒 {:%Y-%m-%d %H:%M}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };
      };
    };
    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        font-weight: bold;
        min-height: 0;
      }

      window#waybar {
        background: rgba(21, 18, 27, 0.8);
        color: #cdd6f4;
      }

      #workspaces button {
        padding: 0 5px;
        background: transparent;
        color: #cdd6f4;
      }

      #workspaces button:hover {
        background: rgba(0, 0, 0, 0.2);
      }

      #workspaces button.active {
        background: #7aa2f7;
        color: #1e1e2e;
      }

      #workspaces button.urgent {
        background: #f38ba8;
        color: #1e1e2e;
      }

      #battery,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #clock {
        padding: 0 10px;
        margin: 0 5px;
      }

      #battery {
        color: #a6e3a1;
      }

      #battery.warning {
        color: #f9e2af;
      }

      #battery.critical {
        color: #f38ba8;
      }

      #network {
        color: #89b4fa;
      }

      #pulseaudio {
        color: #cba6f7;
      }

      #cpu {
        color: #f5c2e7;
      }

      #memory {
        color: #fab387;
      }

      #clock {
        color: #89dceb;
      }
    '';
  };

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

    # Hyprland related
    waybar
    swaybg
    swaylock
    wl-clipboard
    wf-recorder
    grimblast
    hyprpaper
    hyprpicker
    hypridle
    hyprlock

    # Terminal Multiplexers
    tmux
    screen

    # LLVM/Clang toolchain (needed for race detection and C/C++ builds)
    llvmPackages_20.clang-tools
    llvmPackages_20.lld

    # LLVM C++ Standard Library, compiler runtime, and unwind library
    llvmPackages_20.stdenv
    llvmPackages_20.libcxxStdenv
    llvmPackages_20.libcxxClang
    llvmPackages_20.libcxx          # Provides libc++.so, libc++.a (libraries)
    llvmPackages_20.libcxx.dev      # Provides C++ headers
    # do NOT include llvm.libc-full, because it will override glibc
    #llvm.libc-full
    llvmPackages_20.compiler-rt     # Provides libclang_rt.builtins*.a
    llvmPackages_20.compiler-rt.dev # Provides libclang_rt headers
    llvmPackages_20.libunwind       # Provides libunwind for exception handling
    llvmPackages_20.libunwind.dev   # Provides libunwind headers

    libclang libclang.dev libclang.lib

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
    #xz
    #zstd

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
    iperf2
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
    flutter
    android-studio
    android-tools
    android-udev-rules

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
    flameshot
    #(flameshot.override { enableWlrSupport = true; })
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
    #rpi-imager

    #silly
    cmatrix
    sl
    vectoroids # game
    # https://feralinteractive.github.io/gamemode/
    # sameboy

    #gpu monitoring
    lact
  ];

  # vscode
  # https://nixos.wiki/wiki/Visual_Studio_Code
  # https://github.com/thexyno/nixos-config/blob/main/hm-modules/vscode/default.nix
  # nix run github:nix-community/nix-vscode-extensions# -- --list-extensions
  # https://mynixos.com/home-manager/options/programs.vscode
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      dart-code.dart-code
      dart-code.flutter
      golang.go
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

  # set at flake.nix level
  nixpkgs.config.allowUnfree = true;

  home.stateVersion = "24.11";
}
