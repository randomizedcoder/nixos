#
# arm/pi-bob/nix/packages.nix
#
# System-wide tools, available to every user (bob, sebastian, das, root).
# Kept at the system level (rather than per-user home.nix) so all three users
# get the same toolbox without 3x duplication.
#
# Covers: editors, a C/autotools dev chain for iperf2 development, networking
# diagnostics, and general shell utilities.
#
# NOTE on networking tools: we deliberately use iputils (ping) + net-tools
# (ifconfig) + traceroute, and do NOT include inetutils, to avoid two packages
# providing the same `ping`/`ifconfig`/`traceroute` binaries in one profile.
#

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # editors
    vim
    # terminal Emacs. Cross-compile caveats for this SD image (x86_64 -> aarch64):
    #  - the GUI build (like vim-full) won't cross-compile -> use the -nox variant;
    #  - withTreeSitter pulls tree-sitter 0.26.x, whose Rust/bindgen build runs
    #    clang with the wrong target against aarch64 glibc headers and fails on
    #    ARM SVE types (__SVFloat32_t);
    #  - withMailutils pulls guile, which fails to cross-compile (patch hunk
    #    rejected). emacs falls back to its built-in movemail without it.
    # Both features are optional; disable them so the image cross-builds.
    (emacs-nox.override {
      withTreeSitter = false;
      withMailutils = false;
    })
    nano

    # terminal multiplexers
    tmux
    screen

    # iperf2 / C development (autotools toolchain + debuggers)
    gcc
    gnumake
    autoconf
    automake
    libtool
    pkg-config
    binutils
    gdb
    valgrind
    python3

    # networking diagnostics
    tcpdump
    iputils # ping
    traceroute
    net-tools # ifconfig, netstat, route
    ethtool
    iproute2
    mtr
    fping
    netcat-gnu

    # inspection / debug
    pciutils
    usbutils
    lshw
    hwloc
    lsof
    strace
    killall

    # general utilities
    git
    htop
    btop
    tree
    wget
    curl
    file
    which
    jq
    gawk
    rsync
    gzip
    zstd
    xz
    zip
    unzip
  ];
}
