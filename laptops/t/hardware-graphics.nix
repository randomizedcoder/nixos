#
# nixos/laptops/t/hardware-graphics.nix
#

# example: https://github.com/colemickens/nixcfg/blob/1915d408ea28a5b7279f94df7a982dbf2cf692ef/mixins/gfx-nvidia.nix

{ config,
  pkgs,
  lib,
  ...
}:
{
  # Use hardware.graphics for graphics configuration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs.unstable; [
      # VA-API support
      libva
      libva-utils
      vaapiIntel
      intel-media-driver

      # VDPAU support
      vaapiVdpau
      libvdpau
      libvdpau-va-gl
      vdpauinfo

      # OpenGL support
      libGLU
      libGL
    ];
  };

    # TODO try displaylink
  # https://nixos.wiki/wiki/Displaylink
  # nix-prefetch-url --name displaylink-600.zip https://www.synaptics.com/sites/default/files/exe_files/2024-05/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.0-EXE.zip
  #services.xserver.videoDrivers = [ "displaylink" "modesetting" ];

  # https://wiki.nixos.org/wiki/NVIDIA
  # https://nixos.wiki/wiki/Nvidia
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/hardware/video/nvidia.nix
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/hardware/video/nvidia.nix
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement = {
      enable = true;
      finegrained = true;
    };

    open = false;
    nvidiaSettings = true;
    package = pkgs.unstable.linuxPackages.nvidiaPackages.production;

    prime = {
      offload.enable = true;
      # Intel GPU
      intelBusId = "PCI:0:2:0";
      # NVIDIA is your secondary GPU
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  services.xserver = {
    enable = true;
    videoDrivers = [ "modesetting" "nvidia" ];
    displayManager = {
      gdm.enable = true;
    };

    # Enable the GNOME Desktop Environment
    desktopManager = {
      gnome.enable = true;
      plasma5.enable = false;
      xterm.enable = false;
    };
    # https://discourse.nixos.org/t/help-with-setting-up-a-different-desktop-environment-window-manager/15025/6

    # Configure keymap in X11
    xkb.layout = "us";
    xkb.variant = "";
  };

  # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/12?u=randomizedcoder
  # https://gist.github.com/chrisheib/162c8cad466638f568f0fb7e5a6f4f6b#file-config-nix-L193
  environment.variables = {
    # VA-API configuration
    LIBVA_DRIVER_NAME = "iHD";
    LIBVA_DRIVER_FALLBACK = "nvidia";

    # NVIDIA configuration
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";

    # Wayland configuration
    EGL_PLATFORM = "wayland";
    WLR_NO_HARDWARE_CURSORS = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    NIXOS_OZONE_WL = "1";

    # NVIDIA library paths
    CUDA_PATH = "${config.hardware.nvidia.package}/lib";
    EXTRA_LDFLAGS = "-L/lib -L${config.hardware.nvidia.package}/lib";
    EXTRA_CCFLAGS = "-I/usr/include";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:${config.hardware.nvidia.package}/lib";

    # Qt applications
    QT_QPA_PLATFORM = "wayland";
  };

  # Session variables for Electron apps
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    ELECTRON_EXTRA_LAUNCH_ARGS = "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,UseOzonePlatform --ozone-platform=wayland";
  };

  # Browser configuration
  nixpkgs.config.chromium.commandLineArgs = "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,UseOzonePlatform --ozone-platform=wayland";
  nixpkgs.config.firefox.commandLineArgs = "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,UseOzonePlatform --ozone-platform=wayland";

  nixpkgs.config.allowAliases = false;
}

    # i tried prime, but it didn't seem to work
    # prime = {
    #   # ([[:print:]]+[:@][0-9]{1,3}:[0-9]{1,2}:[0-9])?'
    #   # 00:02.0 VGA compatible controller: Intel Corporation CometLake-H GT2 [UHD Graphics] (rev 05)
    #   intelBusId = "PCI:0:2:0";
    #   # 01:00.0 VGA compatible controller: NVIDIA Corporation TU117GLM [Quadro T2000 Mobile / Max-Q] (rev a1)
    #   nvidiaBusId = "PCI:1:0:0";
    #   sync.enable = true;
    #   #offload = {
    #   #  enable = true;
    #   #  #sync.enable = true;
    #   #  enableOffloadCmd = true;
    #   #};
    # };

# [LOG] GPU information:
# 00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-H GT2 [UHD Graphics] [8086:9bc4] (rev 05) (prog-if 00 [VGA controller])
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117GLM [Quadro T2000 Mobile / Max-Q] [10de:1fb8] (rev a1) (prog-if 00 [VGA controller])