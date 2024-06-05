#!/usr/bin/bash
#
sudo cp ./*.nix /etc/nixos/
sudo nixos-rebuild switch

#sudo ln -s /run/current-system/sw/bin/bash /usr/bin/bash