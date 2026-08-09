# super-b deploy helper. Per-node vars only:
NAME = b
HOST = 10.241.10.11

EXPECTED_HOSTNAME := super-$(NAME)
ACTUAL_HOSTNAME := $(shell hostname)

# --- from your WORKSTATION ---
sync:
	cp ../networking.nix ../routing.nix ./
	rsync -av --exclude '*.2026_*' --exclude 'result' ./ das@$(HOST):nixos/super/$(NAME)/

# Push, then flake-switch over SSH. NOTE: the network restart mid-switch will close this
# SSH session — that's cosmetic, the switch still completes. Prefer `make local` over SOL.
rebuild: sync
	ssh -t das@$(HOST) 'sudo nixos-rebuild switch --flake /home/das/nixos/super/$(NAME)#super --option extra-experimental-features "nix-command flakes"'

# --- run ON the node itself (e.g. over the SOL console) --- hostname-guarded.
local: check_hostname
	sudo nixos-rebuild switch --flake .#super --option extra-experimental-features "nix-command flakes"

check_hostname:
ifeq ($(ACTUAL_HOSTNAME),$(EXPECTED_HOSTNAME))
	@echo "Hostnames match: $(ACTUAL_HOSTNAME)"
else
	@echo "Error: Hostname does not match. Expected: $(EXPECTED_HOSTNAME), Got: $(ACTUAL_HOSTNAME)"
	@exit 1
endif

build:
	nix build .#nixosConfigurations.super.config.system.build.toplevel --no-link

# DNS band-aid — run ON the node if /etc/resolv.conf has no nameservers and you need to fetch.
dns:
	printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf

pull-hw:
	scp das@$(HOST):/etc/nixos/hardware-configuration.nix ./hardware-configuration.nix
