# wireguard.nix — STUB restored 2026-08-22
#
# blackbox.nix imports this file for `wireguardPeers` (to build blackbox ICMP targets
# for WireGuard peer /32s). The original file was deleted, which left the flake
# unbuildable (hp4's running system dates to 2025-06-30, before the deletion).
#
# This empty stub restores buildability: no WireGuard peers are monitored. Prometheus
# does not consume the wireguard targets, so blackbox behaviour is unchanged in practice.
#
# If you previously monitored WireGuard peers here, restore them in this shape:
#   wireguardPeers = {
#     "<peerName>" = { name = "<label>"; cakePolicy = "<policy>"; allowedIPs = [ "10.0.0.2/32" ]; };
#   };
{ config, lib, pkgs, ... }:
{
  wireguardPeers = { };
}
