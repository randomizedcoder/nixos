# home-ssh-config-runpod.nix
#
# SSH config for the RunPod fleet, reached through the NordLayer VPN sandbox
# (`vpn-jump` -> the nordlayer-sandbox container). Split out of
# home-ssh-config.nix so the fleet/jump plumbing lives on its own.
#
# Contributes its Host blocks to `local.sshExtraConfig` (defined in
# home-ssh-config.nix) and adds the fleet-socks SOCKS-master helpers to PATH.
#
# NOTE on $(id -u): kept literal here so bash expands it when ~/.ssh/config is
# generated at login (see home-ssh-config.nix). Do not escape it.

{ config, pkgs, lib, ... }:

{
  # mkBefore -> this block sorts ahead of other sshExtraConfig contributors
  # (e.g. nfb). Placement is cosmetic: none of these patterns overlap, and the
  # default `Host *` is always emitted last by the generator.
  local.sshExtraConfig = lib.mkBefore ''
    # Jump entry into the NordLayer sandbox container on l.
    # The container's sshd is reachable directly via the host-container veth at
    # 10.99.0.2:22 from this machine (l) -- see desktop/l/nordlayer-sandbox.nix.
    # Inside the sandbox, run "nordlayer connect GATEWAY" once, then any
    # ProxyJump-ed host below traverses the VPN tunnel.
    Host vpn-jump
      Hostname 10.99.0.2
      User vpn
      IdentityFile ~/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
      UserKnownHostsFile ~/.ssh/known_hosts.d/vpn-jump
      ServerAliveInterval 30
      # Disable connection multiplexing on the proxy hops. Sharing one
      # master across many ProxyJump-ed destination ssh's (the prod fleet
      # has ~3500 hosts) produced sporadic channel races and "ssh eof
      # before prompt" at ~50% rate during 100-host fleet walks. Each
      # destination ssh gets a fresh handshake to vpn-jump now; costs
      # ~1 RTT extra per ssh, but yields 100% success instead of 50%.
      ControlMaster no
      ControlPath none

    # PROD fleet jump host behind the NordLayer VPN. Every prod-fleet ssh
    # (Host 100.* below) forwards through it. Dev uses dev-runpod-jump instead
    # (see the DEV fleet block below).
    Host runpod-jump
      Hostname doc-ssh1.runpod.io
      User rp_das
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      ProxyJump vpn-jump
      # See vpn-jump above for the multiplex-on-jump-host rationale.
      # This is the inner proxy; every prod fleet ssh forwards through it.
      ControlMaster no
      ControlPath none

    # SOCKS master for FAST fleet collection. Start it with fleet-socks-up,
    # stop with fleet-socks-down (both are on PATH; defined in this file).
    # fleet-socks-up runs: ssh -fN -M -S CTL -D 1080 fleet-socks -- ONE persistent
    # connection (l -> vpn-jump -> runpod-jump, a single NordLayer tunnel crossing)
    # that opens a local SOCKS proxy on 127.0.0.1:1080. While it's up, the
    # "Match host 100.* ... :1080" block below routes ALL prod-fleet ssh through it
    # as multiplexed channels instead of each re-handshaking both jump hops -- which
    # lets fleet walks run at -P 80 (~100%) where the per-connection ProxyJump path
    # collapses at -P 40 over the VPN. Full rationale + measurements:
    # runpod/fleet-snapshots scripts/fleet-snapshot/README.md "SOCKS fast path".
    Host fleet-socks
      Hostname doc-ssh1.runpod.io
      User rp_das
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      ProxyJump vpn-jump
      ControlMaster no
      ControlPath none
      ExitOnForwardFailure yes
      ServerAliveInterval 30

    # RunPod dev jump host behind the same NordLayer VPN.
    Host dev-runpod-jump
      Hostname dev-docssh.runpod.io
      User rp_das
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      ProxyJump vpn-jump
      # Match runpod-jump (above) for the dev fleet path.
      ControlMaster no
      ControlPath none

    # -- DEV fleet -----------------------------------------------------------
    # Prod and dev are DIFFERENT reachability domains (verified 2026-07-01):
    #   prod : vpn-jump -> runpod-jump      , rp_das@:22 (real sshd, non-root +
    #          key id_ed25519_runpod          passwordless sudo) -> "Host 100.*"
    #                                         below (the default). Legacy daemon
    #                                         path sshpower@:2009 via rp-daemon.
    #   dev  : vpn-jump -> dev-runpod-jump  , rp_das@:22 (real sshd, non-root),
    #          key id_ed25519_runpod        -> THIS block.
    # They share the 100.64.0.0/10 overlay ADDRESSING, but reachability is
    # partitioned by jump: the prod jump can't reach the dev 100.65.0.x segment,
    # and the dev jump reaches it. The 100.65.0.0/24 segment is EXCLUSIVELY dev
    # (0 prod hosts, ~116 dev), so route the whole /24 to the dev jump here. This
    # must sit BEFORE "Host 100.*" (first-match-wins) so dev IPs don't fall
    # through to the prod wildcard.
    #
    # NOTE 1: the 4 dev "DummyBox" hosts on 100.65.12.x share that /24 with prod
    #         and answer via the PROD jump, so they intentionally use "Host 100.*"
    #         below, not this block.
    # NOTE 2: assumes 100.65.0.0/24 stays dev-only; if a prod host ever lands
    #         there it would mis-route to the dev jump.
    Host 100.65.0.*
      User rp_das
      Port 22
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      ProxyJump vpn-jump,dev-runpod-jump
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
      # All dev hosts here are real sshd:22, so multiplexing is safe/beneficial.
      ControlMaster auto
      ControlPath /run/user/$(id -u)/ssh/master-%n-%r@%h:%p

    # SOCKS fast path (auto-detect). When a SOCKS master is listening on
    # 127.0.0.1:1080 (i.e. fleet-socks-up has been run), route the prod fleet
    # through it as a ProxyCommand instead of the per-connection ProxyJump below.
    # This block comes BEFORE "Host 100.*" so its ProxyCommand is obtained first
    # (ssh uses the first-specified of ProxyCommand/ProxyJump); when the master is
    # down the exec test returns non-zero, this block is skipped, and the
    # "Host 100.*" ProxyJump applies -- so nothing breaks when no master is up.
    # The dev /24 (100.65.0.*) is excluded -- it uses the dev-runpod-jump block
    # above, not this prod SOCKS master. socat is provided by home.nix.
    Match host 100.*,!100.65.0.* exec "ss -Htln 'sport = :1080' | grep -q ."
      ProxyCommand socat - SOCKS4A:127.0.0.1:%h:%p,socksport=1080

    # PROD fleet -- the default for every 100.x overlay IP (CGNAT 100.64.0.0/10),
    # reached via runpod-jump as rp_das@:22 (the host's REAL sshd, non-root +
    # passwordless sudo), matching the dev block above. This replaced the old
    # sshpower@:2009 Go-daemon sshd (interactive-only: no scp / tunnels / agent
    # forwarding) once das's id_ed25519_runpod.pub was rolled out for rp_das on
    # the fleet (2026-07-24). NOTE: the dev /24 (100.65.0.*) is diverted to the
    # dev jump by the "Host 100.65.0.*" block above, which matches first;
    # everything else here is prod. Long-form equivalent of this block:
    #   ssh -J vpn-jump,runpod-jump -i ~/.ssh/id_ed25519_runpod -o IdentitiesOnly=yes \\
    #       -o StrictHostKeyChecking=no -l rp_das <IP>
    # With this block: ssh 100.65.25.46 (or, with a master up, via SOCKS).
    #
    # FALLBACK: the id_ed25519_runpod key is on the "vast majority" but not ALL
    # hosts (see runpod/fleet-snapshots rp-das-audit). A host that answers
    # "Permission denied (publickey)" or lacks rp_das is still reachable via the
    # legacy sshpower@:2009 Go-daemon -- use rp-daemon <IP> (PATH wrapper
    # defined in home.packages below). To revert the whole fleet to the daemon,
    # swap the four commented "legacy Go-daemon" lines back in below.
    Host 100.*
      User rp_das
      Port 22
      IdentityFile ~/.ssh/id_ed25519_runpod
      # legacy Go-daemon sshd (fallback via rp-daemon): User sshpower / Port 2009 / IdentityFile ~/.ssh/id_rsa_runpod
      IdentitiesOnly yes
      ProxyJump vpn-jump,runpod-jump
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR

    # RunPod storage servers (s2-1[0-2]-stor) -- AMD EPYC 9655, 2x900GB + 2x7TB.
    # Reachable from l by chaining one more hop off the runpod overlay:
    # l -> vpn-jump -> runpod-jump -> 100.65.31.206 -> canopy@10.x.x.x
    # Each host has two NICs: 10.2.2.x (primary) and 10.3.2.x (alt subnet).
    # Long-form equivalent:
    #   ssh -J vpn-jump,runpod-jump,100.65.31.206 -i ~/.ssh/id_ed25519_runpod \\
    #       -o IdentitiesOnly=yes canopy@10.2.2.10
    # With this block: ssh s2-10-stor   (or ssh 10.2.2.10 / ssh 10.3.2.10)
    Host s2-10-stor
      Hostname 10.2.2.10
    Host s2-11-stor
      Hostname 10.2.2.11
    Host s2-12-stor
      Hostname 10.2.2.12

    Host s2-10-stor s2-11-stor s2-12-stor 10.2.2.10 10.2.2.11 10.2.2.12 10.3.2.10 10.3.2.11 10.3.2.12
      User canopy
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      ProxyJump 100.65.31.206
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR

    # -- Hive DC -------------------------------------------------------------
    # Hive datacenter bastion. PUBLIC IP, reached DIRECTLY from l -- NOT through
    # the NordLayer VPN (verified 2026-07-22: 63.141.33.1:22 is open direct).
    # Identifies as "runpod-bastion"; authenticates as runpod@ with the runpod
    # ed25519 key. It is the gateway into the Hive private net (10.2.5.0/24).
    #   ssh hivejump
    Host hivejump
      Hostname 63.141.33.1
      User runpod
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new

    # Hive private-net host, reached by chaining through hivejump (above):
    #   l -> hivejump (runpod@63.141.33.1) -> root@10.2.5.148
    # Long-form equivalent: ssh -J hivejump root@10.2.5.148
    # With this block:      ssh 10.2.5.148
    # NOTE: root@10.2.5.148 accepts publickey ONLY. As of 2026-07-22 none of
    # das's keys are in its authorized_keys -- add id_ed25519_runpod.pub to
    # /root/.ssh/authorized_keys on the target (out-of-band) for this to auth.
    # To cover the whole segment, widen the pattern to "Host 10.2.5.*".
    Host 10.2.5.148
      User root
      IdentityFile ~/.ssh/id_ed25519_runpod
      IdentitiesOnly yes
      ProxyJump hivejump
      StrictHostKeyChecking accept-new
  '';

  # fleet-socks-up / fleet-socks-down -- lifecycle for the SOCKS master that
  # the "Match host 100.* ... :1080" block above auto-uses. Bring it up before a
  # fleet walk (then run snapshot-parallel.sh at -P 80), tear it down after. Uses
  # a control socket in the tmpfs runtime dir so it can be checked/closed cleanly.
  # See runpod/fleet-snapshots collector README.
  home.packages = with pkgs; [
    (writeShellApplication {
      name = "fleet-socks-up";
      text = ''
        ctl="/run/user/$(id -u)/ssh/fleet-socks.ctl"
        if ssh -O check -S "$ctl" fleet-socks 2>/dev/null; then
          echo "fleet-socks: already up (SOCKS on 127.0.0.1:1080)"
          exit 0
        fi
        ssh -fN -M -S "$ctl" -D 1080 -o ExitOnForwardFailure=yes fleet-socks
        echo "fleet-socks: SOCKS master up on 127.0.0.1:1080 (one warm tunnel)"
        echo "  fleet ssh now auto-routes through it; run e.g. snapshot-parallel.sh ... 80"
      '';
    })

    (writeShellApplication {
      name = "fleet-socks-down";
      text = ''
        ctl="/run/user/$(id -u)/ssh/fleet-socks.ctl"
        if ssh -O exit -S "$ctl" fleet-socks 2>/dev/null; then
          echo "fleet-socks: stopped (fleet ssh reverts to per-connection ProxyJump)"
        else
          echo "fleet-socks: not running"
        fi
      '';
    })

    # rp-daemon -- reach a prod host over the LEGACY Go-daemon sshd
    # (sshpower@:2009, key id_rsa_runpod) instead of the default real sshd
    # (rp_das@:22, "Host 100.*" above). Use it for the minority of hosts that
    # don't have das's id_ed25519_runpod key for rp_das (they answer :22 with
    # "Permission denied (publickey)"). The daemon is INTERACTIVE-ONLY: it
    # ignores an ssh exec request and always hands back an interactive shell, so
    # a passed command hangs (this is why the fleet collector drives it with
    # expect). Use it for an interactive shell; we force a pty (-tt).
    #   rp-daemon 100.65.10.159            # interactive root shell on the daemon
    (writeShellApplication {
      name = "rp-daemon";
      text = ''
        if [ "$#" -lt 1 ]; then
          echo "usage: rp-daemon <100.x-ip> [command...]" >&2
          exit 2
        fi
        host=$1; shift
        exec ssh -tt -p 2009 -l sshpower -i ~/.ssh/id_rsa_runpod \
          -o IdentitiesOnly=yes \
          -o ProxyJump=vpn-jump,runpod-jump \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          "$host" "$@"
      '';
    })
  ];
}
