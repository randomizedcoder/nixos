#
# /etc/nixos/nix-settings.nix  —  identical on every super-* node
#
# Nix daemon tuning, brought over from the other workstation's config.
# Deliberately DROPPED from that host's set: `extra-sandbox-paths = [ "/var/cache/bazel-nix" ]`
# (bazel-nix cache — not present/needed here).
#
{ ... }:

{
  nix = {
    settings = {
      auto-optimise-store = true;                 # hard-link identical store paths
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = "500000000";         # 500 MB
      trusted-users = [ "das" ];
      http-connections = 100;                     # default 25
      max-substitution-jobs = 64;                 # default 16 — faster cache fetches

      # Build parallelism. The source host is a 24-thread Threadripper (max-jobs=1, cores=24 =
      # one big build using all cores). These nodes have 56 threads, BUT `nix-daemon` runs in
      # `system.slice`, which cpu-tuning.nix confines to the reserved pool (0-7,26-35,54-55 =
      # 20 threads) — so a rebuild never spills onto the isolated K8s workload cores, and the
      # cgroup caps effective parallelism at ~20 regardless of `cores`. Hence 16 (within the
      # pool, with headroom for bird/system during a build) rather than the Threadripper's 24.
      # To let builds use all 56 threads you'd move nix-daemon out of the confined slice
      # (separate change), not just raise `cores`.
      max-jobs = 1;
      cores = 16;
    };

    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 10d";
      randomizedDelaySec = "14m";
    };
  };
}
