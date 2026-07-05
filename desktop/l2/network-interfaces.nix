#
# l2/network-interfaces.nix
#
# Static IP configuration for 10GbE NICs
#
# Mellanox ConnectX-4 Lx (mlx5):  enp35s0f0np0, enp35s0f1np1
#   Managed by xdp2.testbed (see configuration.nix). Addresses
#   10.10.2.5/29 (port0) and 10.10.3.5/29 (port1).
# Intel 82599ES (ixgbe):  enp66s0f0, enp66s0f1        -> 10.3.0.1/24, 10.4.0.1/24
# Broadcom (bnxt_en):     enp4s0f0np0, enp4s0f1np1    -> 10.5.0.1/24, 10.6.0.1/24
#
{ config, lib, pkgs, ... }:

{
  # Mellanox ConnectX-4 Lx ports (enp35s0f0np0/enp35s0f1np1) are
  # configured by xdp2.testbed.addresses in configuration.nix — do
  # not also declare them here or networking.interfaces will fight
  # with the testbed module.

  # Intel 82599ES (ixgbe driver) - 10GbE SFI/SFP+
  # CARD NOT INSTALLED (commented out 2026-07-05) - re-enable with the card.
  # networking.interfaces.enp66s0f0 = {
  #   ipv4.addresses = [{
  #     address = "10.3.0.1";
  #     prefixLength = 24;
  #   }];
  # };
  #
  # networking.interfaces.enp66s0f1 = {
  #   ipv4.addresses = [{
  #     address = "10.4.0.1";
  #     prefixLength = 24;
  #   }];
  # };

  # Broadcom (bnxt_en driver) - 10GbE
  # CARD REMOVED / ABANDONED (commented out 2026-07-05) - high idle temps; not
  # coming back. Static IPs on absent enp4s0f0np0/f1np1 spawned address services
  # that waited on missing devices.
  # networking.interfaces.enp4s0f0np0 = {
  #   ipv4.addresses = [{
  #     address = "10.5.0.1";
  #     prefixLength = 24;
  #   }];
  # };
  #
  # networking.interfaces.enp4s0f1np1 = {
  #   ipv4.addresses = [{
  #     address = "10.6.0.1";
  #     prefixLength = 24;
  #   }];
  # };
}
