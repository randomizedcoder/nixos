#
# arm/nix-os-raspberrypi/Makefile
#

# Fake targets
.PHONY: rpi2 rpi4 rpi4

all: rp5

rpi2:
	nix build .#installerImages.rpi02

rp4:
	nix build .#installerImages.rpi4

rp5:
	nix build .#installerImages.rpi5

rp5_on_amd64:
	sudo nix build .#nixosConfigurations.rpi5.config.system.build.sdImage --system aarch64-linux

update:
	sudo nix flake update;

sync:
	rsync -avz ./ 172.16.40.122:/home/das/nixos/arm/nix-os-raspberrypi/ 

# end
