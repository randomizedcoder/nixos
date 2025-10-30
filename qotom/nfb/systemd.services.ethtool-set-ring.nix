#
# nixos/qotom/nfb/systemd.services.ethtool-set-ring.nix
#
{ pkgs, lib, ... }:

let
  networkInterfaces = [ "enp1s0" "enp2s0" "enp3s0" "enp4s0" ];

  rxRingSize = 4096;
  txRingSize = 4096;

  generateEthtoolService = interfaceName: {
    description = "ethtool-${interfaceName}";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-ring ${interfaceName} rx ${toString rxRingSize} tx ${toString txRingSize}";
    };
    wantedBy = [ "network-pre.target" ];
  };

in
{
  systemd.services = lib.genAttrs networkInterfaces (interfaceName: generateEthtoolService interfaceName);
}
