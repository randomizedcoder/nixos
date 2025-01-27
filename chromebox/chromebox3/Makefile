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

try:
	#nix run github:nix-community/nixos-anywhere -- --flake '.#chromebox3' --target-host root@chromebox3
	nix run github:nix-community/nixos-anywhere -- --flake '.#chromebox3' --target-host root@chromebox3

gen_hardware:
	nix run github:numtide/nixos-anywhere -- -f '.#chromebox3' --generate-hardware-config nixos-generate-config ./hardware-configuration.nix

# minutes 10:58
# https://www.youtube.com/watch?v=U_UwzMhixr8
vmtest:
	sudo nix flake update;
	sudo nix flake lock;
#nix run github:numtide/nixos-anywhere -- -f '.#chromebox3' --vm-test --generate-hardware-config nixos-generate-config ./hardware-configuration.nix
	nix run github:numtide/nixos-anywhere -- -f '.#chromebox3' --vm-test