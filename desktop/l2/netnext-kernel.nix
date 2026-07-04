# netnext-kernel.nix
#
# net-next v7.2-rc1 (base b73bc9ca3686) + the series4 flow_dissector fast-path
# framework, baked into the source via the `series4-send` branch of the local
# net-next tree. 12 commits: 7 byte-identical fast-paths (eth_ip/vlan/qinq/
# pppoe/mpls/ipip/gre), per-shape counters + /proc/net/flow_dissector_stats,
# 3 descent RFCs (vxlan/geneve/gtpu inner), and the adaptive auto-enable RFC
# (net.flow_dissector.auto + auto_window_packets).
#
# Built by overriding nixpkgs `linux_testing` (7.1-rc7) so nixpkgs' kernel-
# config machinery is reused instead of shipping a raw .config — only the src
# and version strings change. Pinned by rev for reproducibility.
#
# The patched net/core/flow_dissector.c is compile-verified objtool-clean on
# this exact base. All gates default off (net.flow_dissector.* = 0), so the
# kernel is byte-identical to stock net-next until a gate is flipped; that
# makes it a clean A/B against the same net-next base.
#
# Update the rev when the series4-send branch moves:
#   cd ~/Downloads/net-next && git rev-parse series4-send

{ linux_testing, linuxPackagesFor }:

let
  netNextSeries4 = builtins.fetchGit {
    url = "file:///home/das/Downloads/net-next";
    ref = "series4-send";
    rev = "9efb44752a0cc78e9f5b5685c40735dc4d08e7c5";
  };
in
linuxPackagesFor (linux_testing.override {
  argsOverride = {
    version = "7.2-rc1";
    modDirVersion = "7.2.0-rc1";
    src = netNextSeries4;
    # nixpkgs' linux_testing (7.1-rc7) structured config requests a few
    # options net-next 7.2-rc1 removed/renamed (CRYPTO_DRBG_CTR/HASH,
    # RANDOM_KMALLOC_CACHES). Tolerate the "unused option" mismatch — the
    # kernel falls back to its own defaults for them.
    ignoreConfigErrors = true;
  };
})
