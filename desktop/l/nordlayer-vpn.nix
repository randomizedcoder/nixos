# nordlayer-vpn.nix (host-side wrapper, transitional)
#
# Imports the reusable daemon module (nordlayer-daemon.nix) and adds host
# user `das` to the `nordlayer` group so the host CLI can talk to
# /run/nordlayer/nordlayer.sock without sudo.
#
# Once the sandbox in nordlayer-sandbox.nix is the user-facing entry point
# for VPN access, this file can be removed from configuration.nix's imports
# along with nordlayer-lan-bypass.nix.
#
# CLI usage on host (unchanged):
#   nordlayer login                         # interactive — opens a browser flow
#   nordlayer connect                       # connect to the default gateway
#   nordlayer connect <city|country|group>  # connect to a specific gateway
#   nordlayer disconnect
#   nordlayer status

{ config, pkgs, lib, ... }:

{
  imports = [ ./nordlayer-daemon.nix ];

  # Add `das` to nordlayer group so the CLI can use the socket without sudo.
  # NOTE: `das` must log out and back in (or run `newgrp nordlayer`) after the
  # first activation that adds them to this group; existing sessions keep the
  # old supplementary-group set.
  users.users.das.extraGroups = [ "nordlayer" ];
}
