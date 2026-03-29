#
# l2/network-interfaces.nix
#
# Static IP configuration for 10GbE NICs
#
# Intel X710 (i40e):      enp35s0f0np0, enp35s0f1np1  -> 10.1.0.1/24, 10.2.0.1/24
# Intel 82599ES (ixgbe):  enp66s0f0, enp66s0f1        -> 10.3.0.1/24, 10.4.0.1/24
# Broadcom (bnxt_en):     enp4s0f0np0, enp4s0f1np1    -> 10.5.0.1/24, 10.6.0.1/24
#
{ config, lib, pkgs, ... }:

{
  # Intel X710 (i40e driver) - 10GbE SFP+
  networking.interfaces.enp35s0f0np0 = {
    ipv4.addresses = [{
      address = "10.1.0.1";
      prefixLength = 24;
    }];
  };

  networking.interfaces.enp35s0f1np1 = {
    ipv4.addresses = [{
      address = "10.2.0.1";
      prefixLength = 24;
    }];
  };

  # Intel 82599ES (ixgbe driver) - 10GbE SFI/SFP+
  networking.interfaces.enp66s0f0 = {
    ipv4.addresses = [{
      address = "10.3.0.1";
      prefixLength = 24;
    }];
  };

  networking.interfaces.enp66s0f1 = {
    ipv4.addresses = [{
      address = "10.4.0.1";
      prefixLength = 24;
    }];
  };

  # Broadcom (bnxt_en driver) - 10GbE
  networking.interfaces.enp4s0f0np0 = {
    ipv4.addresses = [{
      address = "10.5.0.1";
      prefixLength = 24;
    }];
  };

  networking.interfaces.enp4s0f1np1 = {
    ipv4.addresses = [{
      address = "10.6.0.1";
      prefixLength = 24;
    }];
  };
}
