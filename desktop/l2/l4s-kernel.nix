#
# l4s-kernel.nix
#
# Build the L4S team's kernel with TCP Prague and BBRv3
# Source: https://github.com/L4STeam/linux
#
# WARNING: This will compile a custom kernel which takes a long time!
#

{ config, lib, pkgs, ... }:

let
  # L4S kernel configuration
  l4sKernelPackages = pkgs.linuxPackagesFor (pkgs.linux_latest.override {
    # Apply L4S patches to the latest kernel
    argsOverride = rec {
      # Use the same version as your current kernel
      version = "6.18.3";

      # Fetch from L4S team's repository
      src = pkgs.fetchFromGitHub {
        owner = "L4STeam";
        repo = "linux";
        rev = "testing";  # or specific commit for stability
        # First run will fail - copy the correct hash from error message
        sha256 = lib.fakeSha256;
      };

      # Keep standard kernel config but enable L4S modules
      structuredExtraConfig = with lib.kernel; {
        # TCP Prague congestion control
        TCP_CONG_PRAGUE = module;
        # BBRv3 (if available in the tree)
        TCP_CONG_BBR = module;
        # DualPI2 (already in mainline, but ensure it's enabled)
        NET_SCH_DUALPI2 = module;
        # AccECN support
        TCP_ACCECN = yes;
      };
    };
  });

in {
  # OPTION 1: Use L4S kernel (uncomment to enable)
  # boot.kernelPackages = l4sKernelPackages;

  # OPTION 2: Just document what would be needed
  # This file serves as documentation for how to build L4S kernel
}

#
# INSTRUCTIONS:
#
# 1. First, get the correct sha256 hash:
#    nix-prefetch-github L4STeam linux --rev testing
#
# 2. Replace lib.fakeSha256 with the actual hash
#
# 3. Uncomment: boot.kernelPackages = l4sKernelPackages;
#
# 4. Add to configuration.nix imports:
#    ./l4s-kernel.nix
#
# 5. Rebuild (this will take 30-60+ minutes):
#    sudo nixos-rebuild switch
#
# 6. After reboot, verify:
#    lsmod | grep prague
#    cat /proc/sys/net/ipv4/tcp_available_congestion_control
#
# 7. Enable TCP Prague in sysctl.nix:
#    "net.ipv4.tcp_congestion_control" = "prague";
#

