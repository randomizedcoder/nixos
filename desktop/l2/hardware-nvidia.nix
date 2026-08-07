#
# NVIDIA Quadro P620 (GP107GL, Pascal/sm_61) configuration for l2
#
# Physically present at PCI 41:00.0 (Quadro P620, 2 GB Pascal). l2 is
# AMD-primary for compute (W5700 + MI50); the P620 sits alongside them
# for monitoring / light CUDA / display output. 2 GB is too small for
# llama.cpp inference, so no CUDA llama-cpp instance is wired up.
#
# Driver / kernel constraints (2026-06-14):
#   - R585+ (incl. nixpkgs `latest` = 610.43.02) dropped Maxwell/Pascal/Volta.
#   - `nvidiaPackages.legacy_580` = 580.159.04 is the newest branch that
#     still supports Pascal (GP107). That's "the latest driver" for this card.
#   - Open kernel modules require Turing or newer → `open = false` here.
#
# CUDA toolkit (if a CUDA workload is added later):
#   - `cudaPackages_13` dropped sm_61; pin `cudaPackages_12` for Pascal.
#   - Following l's pattern, no toolkit is installed system-wide; it would
#     come in via a service that opts into `config.cudaSupport = true`.
#
{ config, lib, pkgs, ... }:

{
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    modesetting.enable = false;   # headless box; see hardware-graphics.nix
    open = false;                  # Pascal does not support open modules
    nvidiaPersistenced = false;    # avoid the daemon to keep benchmark jitter low
  };

  # Load the driver and the CUDA unified-memory module at boot. nvidia_drm
  # / nvidia_modeset are intentionally omitted — no display server on l2.
  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];

  # videoDrivers wires NixOS's nvidia plumbing (ldconfig, /run/opengl-driver,
  # nixos-rebuild knowing about the driver). It does NOT start an X server —
  # services.xserver.enable stays false in hardware-graphics.nix.
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];
}
