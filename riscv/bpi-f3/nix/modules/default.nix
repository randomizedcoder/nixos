# Aggregate NixOS module for the Banana Pi BPI-F3 (SpacemiT K1, RISC-V).
#
# Headless mainline target: a recent nixpkgs kernel with the in-tree
# k1-bananapi-f3 device tree (+ an overlay re-adding the SD-card slot) and the
# SpacemiT K1 drivers forced on. No GPU/NPU (vendor-kernel only). Serial / SD /
# eMMC / Ethernet / USB / NVMe work.
{
  imports = [
    ./kernel.nix
    ./hardware.nix
    ./base.nix
    ./sd-image/sd-image-bpi-f3.nix
    ./user-group.nix
    ./sshd-INSECURE.nix
  ];
}
