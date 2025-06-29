#
# nixos/arm/pi5-1/Makefile
#
EXPECTED_HOSTNAME := pi5-1

ACTUAL_HOSTNAME := $(shell hostname)

all: check_hostname rebuild

check_hostname:
ifeq ($(ACTUAL_HOSTNAME),$(EXPECTED_HOSTNAME))
	@echo "Hostnames match: $(ACTUAL_HOSTNAME)"
else
	@echo "Error: Hostname does not match. Expected: $(EXPECTED_HOSTNAME), Got: $(ACTUAL_HOSTNAME)"
	@exit 1
endif

rebuild:
	#sudo cp /home/das/nixos/modules/* /etc/nixos/
	# sudo cp ./*.nix /etc/nixos/
	# sudo nix-channel --update
	# sudo nixos-rebuild switch
	#sudo nix flake update;
	sudo nix --extra-experimental-features nix-command --extra-experimental-features flakes flake update;
	#sudo nix-channel --update;
	sudo nixos-rebuild switch --flake .#pi5-1-os

sync:
	rsync -av /home/das/nixos/arm/pi5-1-os/ pi5-1:/home/das/nixos/arm/pi5-1-os/
	#rsync -av /home/das/nixos/modules/ hp2:/home/das/nixos/modules/

syncIP:
	rsync -av /home/das/nixos/arm/pi5-1-os/ 172.16.40.122:/home/das/nixos/arm/pi5-1-os/
	#rsync -av /home/das/nixos/modules/ hp2:/home/das/nixos/modules/

# end
