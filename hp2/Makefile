#
# nixos/hp2/Makefile
#
all:
	sudo cp /home/das/nixos/modules/* /etc/nixos/
	sudo cp ./*.nix /etc/nixos/
	sudo nixos-rebuild switch

sync:
	rsync -av /home/das/nixos/hp2/ hp2:/home/das/nixos/hp2/
	rsync -av /home/das/nixos/modules/ hp2:/home/das/nixos/modules/

# end