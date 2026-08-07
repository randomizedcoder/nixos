# Custom NixOS kernel package built from the net-next combined-test-rfc-no-patch3
# branch (4 patches: flow_dissector docs + flow_hash_from_keys_small +
# sch_cake adoption + bpf_flow PPPoE).
#
# Builds linuxManualConfig with the .config pulled from hp5's running
# 7.0.1 kernel, reconciled to 7.1.0-rc4 via `make olddefconfig` (already
# done — see hp5-kernel.config in this directory).
#
# Usage from hp5's configuration.nix:
#
#   { pkgs, ... }:
#   let
#     customKernel = pkgs.callPackage /path/to/this/default.nix {};
#   in {
#     boot.kernelPackages = pkgs.linuxPackagesFor customKernel;
#   }
#
# To build locally before pushing to hp5 (faster on a multi-core box):
#
#   nix-build kernel-patches/test-kernel/default.nix
#   nix-copy-closure --to ssh://root@hp5 ./result
#   # then update hp5 configuration.nix + nixos-rebuild boot

{ lib
, stdenv
, linuxKernel
, ...
}:

linuxKernel.manualConfig {
  inherit lib stdenv;

  # 7.1.0-rc4 from net-next at commit 011dab72ddf8234b9bf775fc686318bbf25a50b9
  # (combined-test-rfc-no-patch3 tip). Reported by `make kernelversion` /
  # `make kernelrelease` in the net-next tree.
  version = "7.1.0-rc4-flowdis-pppoe";
  modDirVersion = "7.1.0-rc4";

  # Path to the net-next checkout. The checkout must be on the
  # combined-test-rfc-no-patch3 branch with all 4 patches applied. The Nix
  # path import will hash the entire tree, so .git noise is included
  # but only meaningfully affects hashing cost, not build correctness.
  src = builtins.path {
    path = /home/das/Downloads/net-next-no-patch3;
    name = "net-next-combined-test-rfc-no-patch3";
    filter = path: type:
      # Exclude .git noise and stale build artifacts to keep the
      # source closure smaller; nothing in these affects the build.
      let base = baseNameOf path; in
      base != ".git"
      && base != ".tmp_versions"
      && !(lib.hasSuffix ".o.cmd" base)
      && !(lib.hasSuffix ".cmd" base);
  };

  # Config file pulled from hp5's running 7.0.1 kernel, then run through
  # `make olddefconfig` in net-next to reconcile to 7.1.0-rc4 symbols.
  # Tweaks applied for the build env (see build-validation.md):
  #   - CONFIG_DEBUG_INFO_BTF=n
  #     (avoids the in-tree libbpf vs nix-libelf-0.8.13 skew during
  #     resolve_btfids — Nix should handle this correctly via its
  #     elfutils buildInputs, but kept disabled here for parity with
  #     the validated build)
  #   - CONFIG_SYSTEM_TRUSTED_KEYRING=n, CONFIG_MODULE_SIG=n
  #     (avoids openssl-dev dependency for module signing — not
  #     needed for our test runs)
  configfile = ./hp5-kernel.config;

  # Required for linuxManualConfig to read constants out of the config
  # file at evaluation time (e.g. CONFIG_MODULES detection for
  # nixpkgs's kernel build logic).
  allowImportFromDerivation = true;
}
