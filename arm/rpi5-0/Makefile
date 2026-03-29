#
# nixos/arm/rpi5-0/Makefile
#
EXPECTED_HOSTNAME := rpi5-0

ACTUAL_HOSTNAME := $(shell hostname)

# Default target: build the SD card image
all: image

image:
	nix build .#nixosConfigurations.rpi5-0.config.system.build.sdImage
	@echo ""
	@echo "Image built successfully. Output in ./result/sd-image/"
	@echo "Flash with:"
	@echo "  sudo dd if=\$$(readlink -f ./result/sd-image/*.img) of=/dev/sdX bs=4M status=progress conv=fsync"

update:
	nix flake update

lock:
	nix flake lock

check_hostname:
ifeq ($(ACTUAL_HOSTNAME),$(EXPECTED_HOSTNAME))
	@echo "Hostnames match: $(ACTUAL_HOSTNAME)"
else
	@echo "Error: Hostname does not match. Expected: $(EXPECTED_HOSTNAME), Got: $(ACTUAL_HOSTNAME)"
	@exit 1
endif

# Use these targets ON the rpi5-0 itself
rebuild: check_hostname
	sudo nixos-rebuild switch --flake .

rebuild_trace: check_hostname
	sudo nixos-rebuild switch --show-trace --flake .

# Build without installing (no root required)
build:
	nix build .#nixosConfigurations.rpi5-0.config.system.build.toplevel --no-link

# Build with output link in ./result
build-link:
	nix build .#nixosConfigurations.rpi5-0.config.system.build.toplevel

impure:
	sudo nixos-rebuild switch --impure --flake .

sync:
	rsync -av /home/das/nixos/arm/rpi5-0/ rpi5-0:/home/das/nixos/arm/rpi5-0/

syncIP:
	rsync -av /home/das/nixos/arm/rpi5-0/ 172.16.40.XXX:/home/das/nixos/arm/rpi5-0/

# end
