#
# nixos/hp0/Makefile
#
sync:
	rsync -av /home/das/nixos/hp0/ hp0wifi:/home/das/nixos/hp0/
	rsync -av /home/das/nixos/modules/ hp0wifi:/home/das/nixos/modules/

all:
	sudo cp ./*.nix /etc/nixos/
	sudo nixos-rebuild switch

# end