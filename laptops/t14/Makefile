#
# nixos/t14/Makefile
#
all:
	sudo cp ../modules/* /etc/nixos/
	sudo cp ./configuration.nix /etc/nixos/
	sudo cp ./home-manager.nix /etc/nixos/
	sudo cp ./prometheus.nix /etc/nixos/
	sudo nixos-rebuild switch

update:
	sudo nix-channel --update
	sudo nixos-rebuild switch
	#nix-shell -p vim

# end
