# Custom NixOS kernel package built from the net-next
# flowdis-fastpath-rfc branch (3 patches: flow_dissect_fast framework +
# eth+IPv4+{TCP,UDP} fast-path + eth+IPv6+{TCP,UDP} fast-path).
#
# Previous version of this file built from combined-test-rfc (series 1+2;
# 4 patches: flow_dissector docs + flow_hash_from_keys_small + sch_cake
# adoption + bpf_flow PPPoE). To go back to that build, check out
# combined-test-rfc in /home/das/Downloads/net-next and revert this file
# to the prior version string + src name.
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

  # 7.1.0-rc4 from net-next at commit 28bc2795d2feac8f95a3b812fbeab1791b4bd29e
  # (flowdis-fastpath-rfc tip). Reported by `make kernelversion` /
  # `make kernelrelease` in the net-next tree.
  version = "7.1.0-rc4-flowdis-fastpath";
  modDirVersion = "7.1.0-rc4";

  # Path to the net-next checkout. The checkout must be on the
  # flowdis-fastpath-rfc branch with the 3-patch series 3 applied.
  # The Nix path import hashes the entire tree, so .git noise is
  # included but only meaningfully affects hashing cost, not build
  # correctness.
  src = builtins.path {
    path = /home/das/Downloads/net-next;
    name = "net-next-flowdis-fastpath-rfc";
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
