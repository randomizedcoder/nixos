#
# l2/gpu-stable.nix
#
# A boot-time SPECIALISATION that swaps l2's net-next 7.2-rc1 kernel for a stable
# one, so the AMD GPUs (MI50 gfx906 32GB, W5700 gfx1010 8GB) can actually be used.
#
# WHY. On the net-next 7.2.0-rc1 kernel (netnext-kernel.nix), amdgpu wedges on ANY
# GPU command submission to these cards. Verified 2026-07-22: ROCm probes
# (rocminfo/rocm-smi/clinfo) hang UNKILLABLY, and even a Vulkan `vulkaninfo`
# *enumeration* hung and then REBOOTED the box (the sp5100_tco hardware watchdog
# fires when amdgpu wedges the kernel, despite `nowatchdog`). Kernel log at the
# time: `amdgpu 0000:44:00.0: Fence fallback timer expired on ring sdma0`.
# So this is a kernel-driver problem, NOT a ROCm-vs-Vulkan userspace one — the fix
# is a stable kernel, where gfx906/Vega20 amdgpu is mature.
#
# WHY A SPECIALISATION rather than changing the default kernel. l2's *primary* role
# is net-next flow_dissector benchmarking (see configuration.nix:17-22), which
# needs that exact kernel. A specialisation adds a *second* boot entry that uses a
# stable kernel, leaving the default (net-next) untouched. The two roles are not
# simultaneous — you boot the one you need.
#
# USE.
#   on l:   make sync
#   on l2:  make              # adds a "gpu-stable" boot entry; RUNNING kernel is
#                             # UNCHANGED — safe, no reboot, no GPU touched.
#   reboot l2, pick the "gpu-stable" entry in systemd-boot -> boots the stable kernel.
#   the DEFAULT entry still boots net-next for benchmark work.
#
# RECOVERY. If the gpu-stable entry fails to boot, pick the base entry in the boot
# menu. On a headless box that may need console/IPMI access — have it ready before
# the first reboot into this.
#
# NEXT (not done yet): once the GPU is confirmed healthy under this kernel (no wedge
# on `vulkaninfo`, then an `ollama-vulkan` generation), the ollama-vulkan service
# should live INSIDE this specialisation so it can only ever run on the stable
# kernel, never in benchmark mode.
#
{ config, lib, pkgs, ... }:
{
  specialisation.gpu-stable.configuration = {
    system.nixos.tags = [ "gpu-stable" ];

    # The whole point: a stable amdgpu instead of net-next's. `pkgs.linuxPackages`
    # is the nixpkgs default (6.18.x on this pin), where Vega20/gfx906 support is
    # long-mature. mkForce overrides configuration.nix's netnext-kernel.nix choice.
    # All active kernel modules (amdgpu, ib_uverbs, rdma_ucm, sch_dualpi2) are
    # in-tree in 6.18, so nothing else needs to change.
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  };
}
