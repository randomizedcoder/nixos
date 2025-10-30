#
# nixos/qotom/nfb/Makefile
#
EXPECTED_HOSTNAME := nfbQotom

ACTUAL_HOSTNAME := $(shell hostname)

all: check_hostname rebuild

check_hostname:
ifeq ($(ACTUAL_HOSTNAME),$(EXPECTED_HOSTNAME))
	@echo "Hostnames match: $(ACTUAL_HOSTNAME)"
else
	@echo "Error: Hostname does not match. Expected: $(EXPECTED_HOSTNAME), Got: $(ACTUAL_HOSTNAME)"
	@exit 1
endif

update:
	sudo nix flake update;

rebuild:
	sudo nixos-rebuild switch --flake .

rebuild_flakes:
	sudo nix --extra-experimental-features 'nix-command flakes' flake update;
	sudo nixos-rebuild switch --flake .#nfbQotom

anywhere:
	nix run github:nix-community/nixos-anywhere -- --flake '.#nfbQotom' --target-host root@172.16.40.184

#nix run github:nix-community/nixos-anywhere -- --flake '.#chromebox3' --target-host root@chromebox3

gen_hardware:
	nix run github:numtide/nixos-anywhere -- -f '.#nfbQotom' --generate-hardware-config nixos-generate-config ./hardware-configuration.nix --target-host root@172.16.40.184

# minutes 10:58
# https://www.youtube.com/watch?v=U_UwzMhixr8
vmtest:
	sudo nix flake update;
	sudo nix flake lock;
#nix run github:numtide/nixos-anywhere -- -f '.#chromebox1' --vm-test --generate-hardware-config nixos-generate-config ./hardware-configuration.nix
	nix run github:numtide/nixos-anywhere -- -f '.#nfbQotom' --vm-test

sync:
	rsync -av /home/das/nixos/qotom/nfb/ 172.16.40.185:/home/das/nixos/qotom/nfb/

lock:
	scp 172.16.40.185:/home/das/nixos/qotom/nfb/flake.lock ./flake.lock
