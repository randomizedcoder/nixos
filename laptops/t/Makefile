#
# nixos/t/Makefile
#
EXPECTED_HOSTNAME := t

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
	sudo cp ../../modules/* /etc/nixos/
	sudo cp ./configuration.nix /etc/nixos/
	sudo cp ./home-manager.nix /etc/nixos/
	sudo cp ./prometheus.nix /etc/nixos/
	sudo nixos-rebuild switch

update:
	sudo nix-channel --update
	sudo nixos-rebuild switch
	#nix-shell -p vim

# end
