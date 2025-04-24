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

update:
	sudo nix flake update;

# end