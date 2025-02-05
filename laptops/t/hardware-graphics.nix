#
# nixos/laptops/t/hardware-graphics.nix
#
{ config,
  pkgs,
  ...
}:
{
  # hardware.opengl.enable = true;
  # was renamed to:
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
      nvidia-vaapi-driver
      vaapiVdpau
      libvdpau
      libvdpau-va-gl
      vdpauinfo
      libva
      libva-utils
      # https://wiki.nixos.org/wiki/Intel_Graphics
      #vpl-gpu-rt
      # added 2025/02/03 not tested
      vaapiIntel
      intel-media-driver
    ];
  };

    # TODO try displaylink
  # https://nixos.wiki/wiki/Displaylink
  # nix-prefetch-url --name displaylink-600.zip https://www.synaptics.com/sites/default/files/exe_files/2024-05/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.0-EXE.zip
  #services.xserver.videoDrivers = [ "displaylink" "modesetting" ];

  # https://wiki.nixos.org/w/index.php?title=NVIDIA
  # https://nixos.wiki/wiki/Nvidia
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/hardware/video/nvidia.nix
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/hardware/video/nvidia.nix
  hardware.nvidia = {

    # This will no longer be necessary when
    # https://github.com/NixOS/nixpkgs/pull/326369 hits stable
    #modesetting.enable = true;
    modesetting.enable = lib.mkDefault true;

    powerManagement = {
      enable = true;
      #finegrained = true;
    };

    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    # prioritry drivers don't compile on 6.10.3
    # Set to false for proprietary drivers -> https://download.nvidia.com/XFree86/Linux-x86_64/565.77/README/kernel_open.html
    open = true;

    nvidiaSettings = true;

    #package = config.boot.kernelPackages.nvidiaPackages.stable;
    #package = config.boot.kernelPackages.nvidiaPackages.stable;
    #package = config.boot.kernelPackages.nvidiaPackages.beta; # <---------- was using this
    #package = config.boot.kernelPackages.nvidiaPackages.production;
    # https://nixos.wiki/wiki/Nvidia#Determining_the_Correct_Driver_Version
    package = pkgs.linuxPackages.nvidia_x11;
  };

  # https://theo.is-a.dev/blog/post/hyprland-adventure/
  #[das@t:~]$ lshw -c video | grep config
  #WARNING: you should run this program as super-user.
  #       configuration: depth=32 driver=nouveau latency=0 resolution=3840,2160
  #       configuration: depth=32 driver=i915 latency=0 resolution=3840,2160
  #
  #[das@t:~]$ lspci -nnk | egrep -i --color 'vga|3d|2d' -A3 | grep 'in use'
  #Kernel driver in use: i915
  #Kernel driver in use: nouveau
  #
  #[das@t:~]$ lspci -nnk | grep -i vga -A2
  #00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-H GT2 [UHD Graphics] [8086:9bc4] (rev 05)
  #Subsystem: Lenovo Device [17aa:22c0]
  #Kernel driver in use: i915
  #--
  #01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117GLM [Quadro T2000 Mobile / Max-Q] [10de:1fb8] (rev a1)
  #Subsystem: Lenovo Device [17aa:22c0]
  #Kernel driver in use: nouveau
  #
  # hwinfo --gfxcard

  services.xserver = {
    enable = true;

    videoDrivers = [ "nvidia" "intel" ];
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/hardware/video/displaylink.nix
    #videoDrivers = [ "nvidia" "displaylink" ];

    # Display Managers are responsible for handling user login
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
    MOZ_DISABLE_RDD_SANDBOX = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
    EGL_PLATFORM = "wayland";
    # prevents cursor disappear when using Nvidia drivers
    WLR_NO_HARDWARE_CURSORS = "1";

    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    NIXOS_OZONE_WL = "1";

    CUDA_PATH = "${pkgs.linuxPackages.nvidia_x11}/lib";
    # export LD_LIBRARY_PATH=${pkgs.linuxPackages.nvidia_x11}/lib
    EXTRA_LDFLAGS = "-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib";
    EXTRA_CCFLAGS = "-I/usr/include";
    LD_LIBRARY_PATH = "$\{LD_LIBRARY_PATH\}:/run/opengl-driver/lib:${pkgs.linuxPackages.nvidia_x11}/lib";
  };
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