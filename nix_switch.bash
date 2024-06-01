#!/run/current-system/sw/bin/bash
#
sudo cp ./*.nix /etc/nixos/
sudo nixos-rebuild switch
