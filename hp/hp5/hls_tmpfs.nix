{ config, pkgs, ... }:

{
  fileSystems."/hls" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "defaults" "size=1G" "mode=1777" "noatime" ];
  };
}