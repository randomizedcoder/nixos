#
# nixos/hp0/Makefile
#
EXPECTED_HOSTNAME := hp0

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
	sudo cp /home/das/nixos/modules/* /etc/nixos/
	sudo cp ./*.nix /etc/nixos/
	sudo nix-channel --update
	sudo nixos-rebuild switch

sync:
	rsync -av /home/das/nixos/hp/hp0/ hp0:/home/das/nixos/hp0/
	rsync -av /home/das/nixos/modules/ hp0:/home/das/nixos/modules/

# end