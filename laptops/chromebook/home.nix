{
  config,
  pkgs,
  ...
}:

{
  # Ghostty configuration
  programs.ghostty = {
    enable = true;
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

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.sessionVariables
  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    QT_QPA_PLATFORM = "wayland";
    TERM = "xterm-256color";
  };

  home.packages = with pkgs; [
    # System/Info Tools
    killall
    lshw
    ncdu
    neofetch
    file
    htop
    btop
    strace

    # Terminal Multiplexers
    tmux
    screen

    # Build Tools
    gnumake
    pkg-config
    shellcheck

    # Scripting/Utils
    python3
    jq
    bc

    # Compression
    bzip2
    gzip
    lz4
    zip
    unzip
    gnutar

    # File Transfer/Management
    rsync
    tree

    # Nix
    nixpkgs-fmt

    # Networking
    ethtool
    iproute2
    tcpdump
    iperf2
    fping
    inetutils # Includes telnet
    netcat-gnu
    net-tools # for netstat

    # Go Development
    # https://nixos.wiki/wiki/Go
    go
    gopls
    golangci-lint
    delve

    # Editors
    helix

    # Media
    vlc

    # Gnome Related / Extensions
    gnome-extension-manager
    gnome-tweaks
    dconf-editor
    gnome-disk-utility
    gnome-usage
    gnome-settings-daemon
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    gnomeExtensions.just-perfection
    gnomeExtensions.vitals
    gnomeExtensions.user-themes
    gnomeExtensions.space-bar
    libgtop

    # Office/Documents
    evince

    # Browsers
    firefox

    # Text Editors
    gedit

    # Containers
    dive
    docker-buildx
  ];

  # vscode
  # https://nixos.wiki/wiki/Visual_Studio_Code
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      golang.go
      ms-azuretools.vscode-docker
      ms-vscode-remote.remote-ssh
      ms-vscode.makefile-tools
      ms-python.python
      redhat.vscode-yaml
      timonwong.shellcheck
      yzhang.markdown-all-in-one
      jnoortheen.nix-ide
      waderyan.gitblame
    ];
  };

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
    settings.user.email = "dave.seddon.ca@gmail.com";
    settings.user.name = "randomizedcoder";
  };

  # https://heywoodlh.io/nixos-gnome-settings-and-keyboard-shortcuts
  # https://rycee.gitlab.io/home-manager/options.xhtml#opt-dconf.settings
  dconf.settings = {
    "org/gnome/desktop/wm/preferences" = {
      button-layout = ":minimize,maximize,above,close";
      num-workspaces = 2;
    };
    "org/gnome/desktop/interface" = {
      clock-show-seconds = true;
      clock-show-weekday = true;
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      font-antialiasing = "grayscale";
      font-hinting = "slight";
      toolkit-accessibility = false;
    };
    "org/gnome/shell" = {
      disable-user-extensions = false;
      favorite-apps = [
        "firefox.desktop"
        "code.desktop"
        "ghostty.desktop"
      ];
    };
  };

  home.stateVersion = "25.11";
}
