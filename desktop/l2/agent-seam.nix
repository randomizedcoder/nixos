#
# agent-seddon — remote seam fleet
#
# l2 hosts agent-seddon "seams" (its replaceable components) over gRPC while the
# agent loop runs on l. `agent --serve-all` puts every enabled seam behind ONE
# endpoint, so this needs exactly one port open rather than one per seam.
#
#   l                                l2
#   ┌────────────┐   gRPC :50100   ┌──────────────────────────┐
#   │ agent loop │ ──────────────► │ agent --serve-all        │
#   │            │                 │ tokenizer/context/policy │
#   └────────────┘                 │ + 11 more seams          │
#                                  └──────────────────────────┘
#
# Verified working 2026-07-22: the loop on l completed a file-writing task with
# tokenizer, context and policy all executing here. Confirmed load-bearing by
# the negative case — with l2 unreachable the same run fails with
# `status: Unavailable, "tcp connect error"` and writes nothing.
#
# Running the fleet (manual for now — see the note at the bottom):
#   systemd-run --unit=agent-seam --collect \
#     /nix/store/…-agent/bin/agent --serve-all --config /tmp/seam.toml
#   systemctl status agent-seam
#
# The seam config needs `[grpc.gateway] listen = "0.0.0.0:50100"`; the default
# is loopback, which is correct for a single host and useless across two.

{ config, lib, pkgs, ... }:

{
  # l2's firewall is ON (firewall.nix is commented out of imports, so NixOS's
  # default applies), unlike l where it is disabled outright. Without this the
  # port is silently unreachable and the loop fails with a bare
  # "tcp connect error" that looks like a bug in the agent.
  #
  # NOTE: the seam transport is UNAUTHENTICATED by design. Anyone who can reach
  # this port can drive these seams. That is acceptable on a private lab LAN and
  # nowhere else. Do NOT open it on a routable interface — and note especially
  # that `--serve-all` includes the `sandbox` and `tools` seams, which execute
  # commands: reaching this port is equivalent to code execution on l2.
  networking.firewall.allowedTCPPorts = [ 50100 ];

  # TODO: a real systemd service instead of `systemd-run`. That needs the agent
  # package available here, which means adding agent-seddon as a flake input to
  # this config (it exports `packages.x86_64-linux.agent`) — or better, having
  # agent-seddon export a `nixosModules.seam-server` that this file just imports.
  # Today the binary is pushed with `nix copy --to ssh://root@l2 ./result`, which
  # works but is not declarative and does not survive a store GC.
}
