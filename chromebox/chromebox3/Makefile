#
# nixos/chromebox/chromebox3/Makefile
#
EXPECTED_HOSTNAME := chromebox3

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
	#sudo cp ./*.nix /etc/nixos/
	#sudo nix-channel --update
	#sudo nixos-rebuild switch
	sudo nix flake update;
	sudo nix-channel --update;
	sudo nixos-rebuild switch --flake .

# minutes 10:58
# https://www.youtube.com/watch?v=U_UwzMhixr8
vmtest:
	sudo nix flake update;
	sudo nix flake lock;
	nix run github:numtide/nixos-anywhere -- -f '.#chromebox3' --vm-test