# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# sudo nixos-rebuild switch
# sudo nix-channel --update
# nix-shell -p vim
# nmcli device wifi connect MYSSID password PWORD
# systemctl restart display-manager.service

{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

# https://nixos.wiki/wiki/FAQ#How_can_I_install_a_package_from_unstable_while_remaining_on_the_stable_channel.3F
# https://discourse.nixos.org/t/differences-between-nix-channels/13998

{
  # https://nixos.wiki/wiki/NixOS_modules
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.11.tar.gz home-manager
      # sudo nix-channel --update
      # tutorial
      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
      #<home-manager/nixos>
      #
      ./sysctl.nix
      ./wireless_desktop.nix
      # sound removed for 24.11
      #./sound.nix
      ./locale.nix
      ./hosts.nix
      ./firewall.nix
      #./systemdSystem.nix
      ./systemPackages.nix
      # home manager is imported in the flake
      #./home.nix
      ./nodeExporter.nix
      ./prometheus.nix
      ./grafana.nix
      # clickhouse
      #./docker-compose.nix
      ./docker-daemon.nix
      #./smokeping.nix
    ];

  # Bootloader.
  boot = {

    loader.systemd-boot = {
      enable = true;
      consoleMode = "max"; # Sets the console mode to the highest resolution supported by the firmware.
      memtest86.enable = true;
    };

    loader.efi.canTouchEfiVariables = true;

    # https://nixos.wiki/wiki/Linux_kernel
    kernelPackages = pkgs.linuxPackages;
    #boot.kernelPackages = pkgs.linuxPackages_latest;
    #boot.kernelPackages = pkgs.linuxPackages_rpi4

    #boot.kernelParams
    # https://github.com/tolgaerok/nixos-2405-gnome/blob/main/core/boot/efi/efi.nix#L56C5-L56C21
    kernelParams = [
      "nvidia-drm.modeset=1"
      "nvidia-drm.fbdev=1"
    ];

    # https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
    # https://nixos.org/manual/nixos/stable/options#opt-boot.binfmt.emulatedSystems
    binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];

    extraModulePackages = with config.boot.kernelPackages; [
      v4l2loopback
      nvidia_x11
    ];

    # https://nixos.wiki/wiki/Libvirt#Nested_virtualization
    #extraModprobeConfig = "options kvm_intel nested=1";
    # https://gist.github.com/chrisheib/162c8cad466638f568f0fb7e5a6f4f6b#file-config_working-nix-L19
    extraModprobeConfig =
      "options nvidia "
      + lib.concatStringsSep " " [
      # nvidia assume that by default your CPU does not support PAT,
      # but this is effectively never the case in 2023
      "NVreg_UsePageAttributeTable=1"
      # This is sometimes needed for ddc/ci support, see
      # https://www.ddcutil.com/nvidia/
      #
      # Current monitor does not support it, but this is useful for
      # the future
      "NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100"
      "options kvm_intel nested=1"
      # # https://nixos.wiki/wiki/OBS_Studio
      ''
        options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
      ''
      ];
  };

  # For OBS
  security.polkit.enable = true;

  nix = {
    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "weekly";                  # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";
    };
  };

  # https://nixos.wiki/wiki/Networking
  networking.hostName = "t";

  time.timeZone = "America/Los_Angeles";

  # Nouveau is enabled by default whenever graphics are enabled
  # This name will change to hardware.opengl.enable, with 24.11
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      vdpauinfo             # sudo vainfo
      libva-utils           # sudo vainfo
      # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
      nvidia-vaapi-driver
      vaapiVdpau
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

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement = {
      enable = true;
      #enable = false;
      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or newer).
      #finegrained = true;
      #finegrained = false;
    };

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    # prioritry drivers don't compile on 6.10.3
    # Set to false for proprietary drivers -> https://download.nvidia.com/XFree86/Linux-x86_64/565.77/README/kernel_open.html
    open = true;

    # Enable the Nvidia settings menu,
	  # accessible via `nvidia-settings`.
    #nvidiaSettings = false;
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    #package = config.boot.kernelPackages.nvidiaPackages.stable;
    #package = config.boot.kernelPackages.nvidiaPackages.stable;
    #package = config.boot.kernelPackages.nvidiaPackages.beta; # <---------- was using this
    #package = config.boot.kernelPackages.nvidiaPackages.production;
    # https://nixos.wiki/wiki/Nvidia#Determining_the_Correct_Driver_Version
  };

  services.xserver = {
    enable = true;

    videoDrivers = [ "nvidia" ];

    # Display Managers are responsible for handling user login
    displayManager = {
      gdm.enable = true;
    };

    # Enable the GNOME Desktop Environment.
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

  # https://nixos.wiki/wiki/NixOS_Wiki:Audio
  hardware.pulseaudio.enable = false; # Use Pipewire, the modern sound subsystem

  security.rtkit.enable = true; # Enable RealtimeKit for audio purposes

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # Uncomment the following line if you want to use JACK applications
    # jack.enable = true;
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

  services.lldpd.enable = true;

  services.openssh.enable = true;

  services.timesyncd.enable = true;

  services.fstrim.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  services.udev.packages = [ pkgs.gnome-settings-daemon ];
  # services.udev.packages = [ pkgs.gnome.gnome-settings-daemon ];

  services.bpftune.enable = true;

  systemd.services.modem-manager.enable = false;
  systemd.services."dbus-org.freedesktop.ModemManager1".enable = false;

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # https://nixos.wiki/wiki/Printing
  services.printing.enable = true;


  # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/12?u=randomizedcoder
  # https://gist.github.com/chrisheib/162c8cad466638f568f0fb7e5a6f4f6b#file-config-nix-L193
  environment.variables = {
    MOZ_DISABLE_RDD_SANDBOX = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
    EGL_PLATFORM = "wayland";
    WLR_NO_HARDWARE_CURSORS = "1";

    #MOZ_ENABLE_WAYLAND = "1";
    #XDG_SESSION_TYPE = "wayland";
    NIXOS_OZONE_WL = "1";
  };

  environment.sessionVariables = {
    TERM = "xterm-256color";
    #MY_VARIABLE = "my-value";
    #ANOTHER_VARIABLE = "another-value";
  };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" "networkmanager" "kvm" "libvirtd" "docker" "video" ];
    # users.extraGroups.docker.members = [ "das" ];
    packages = with pkgs; [
    ];
    # https://nixos.wiki/wiki/SSH_public_key_authentication
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    vim
    curl
    wget
    tcpdump
    iproute2
    nftables
    iptables
    pciutils
    usbutils
    pciutils
    virt-manager
    cudatoolkit
    pkgs.gnomeExtensions.appindicator
    # #nvidia
    # vdpauinfo             # sudo vainfo
    # libva-utils           # sudo vainfo
    # # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
    # nvidia-vaapi-driver
	  # libvdpau
  	# libvdpau-va-gl
 	  # vdpauinfo
	  # libva
    # libva-utils
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };

  # https://wiki.hyprland.org/Nix/Hyprland-on-NixOS/
  programs.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  programs.chromium.enable = true;
  # programs.chromium.package = pkgs.google-chrome;
  # https://nixos.wiki/wiki/Chromium#Enabling_native_Wayland_support
  nixpkgs.config.chromium.commandLineArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland";
  #programs.chromium.commandLineArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland";

#dD
  # programs.firefox.enable = true;
  # # # https://github.com/TLATER/dotfiles/blob/master/nixos-modules/nvidia/default.nix
  # programs.firefox.preferences = {
  #   "media.ffmpeg.vaapi.enabled" = true;
  #   "media.rdd-ffmpeg.enabled" = true;
  #   "media.av1.enabled" = true; # Won't work on the 2060
  #   "gfx.x11-egl.force-enabled" = true;
  #   "widget.dmabuf.force-enabled" = true;
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  #system.stateVersion = "23.11";

  system.stateVersion = "24.05";

  virtualisation.containers = {
    ociSeccompBpfHook.enable = true;
  };

  # # https://nixos.wiki/wiki/Podman
  # virtualisation.podman = {
  #   enable = true;
  #   dockerCompat = true;
  #   defaultNetwork.settings.dns_enabled = true;
  #   autoPrune.enable = true;
  # };
  # #virtualisation.oci-containers.backend = "podman";
  # # virtualisation.oci-containers.containers = {
  # #   container-name = {
  # #     image = "container-image";
  # #     autoStart = true;
  # #     ports = [ "127.0.0.1:1234:1234" ];
  # #   };
  # # };

  # https://nixos.wiki/wiki/Virt-manager
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # guest
  # services.qemuGuest.enable = true;
  # services.spice-vdagentd.enable = true;

  # https://wiki.nixos.org/wiki/Laptop
}
