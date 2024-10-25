#
# nixos/hp5/Makefile
#

all:
	sudo cp /home/das/nixos/modules/* /etc/nixos/
	sudo cp ./*.nix /etc/nixos/
	sudo nix-channel --update
	sudo nixos-rebuild switch

sync:
	rsync -av /home/das/nixos/hp5/ hp5:/home/das/nixos/hp5/
	rsync -av /home/das/nixos/modules/ hp5:/home/das/nixos/modules/
# end