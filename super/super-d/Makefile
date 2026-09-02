# super-d deploy helper. NO root SSH: reach the box as `das` (key) + passwordless sudo.
#
#   on the LAPTOP:   make sync     # rsync this dir -> super-d:/home/das/nixos/super/super-d
#   on SUPER-D:      make          # = nixos-rebuild switch (hostname-guarded)
#   from LAPTOP:     make rebuild  # sync + switch over SSH in one shot
#
# NAME -> hostname super-d ; DIR -> this folder / path on the box.
# (No inline comments on these — Make would keep the trailing spaces in the value.)
NAME := d
DIR := super-d
HOST := 10.241.10.13
JUMP := nfb-vpn
# NB: the '#' is escaped (\#) — bare '#' starts a Make comment, which would drop
# the '#super' attr and make nixos-rebuild fall back to nixosConfigurations.super-d.
FLAKE := /home/das/nixos/super/$(DIR)\#super

EXPECTED_HOSTNAME := super-$(NAME)
ACTUAL_HOSTNAME := $(shell hostname)

# Bare `make` = apply locally (on the node). The hostname guard means running it
# by accident on the laptop fails safely instead of rebuilding the wrong machine.
.DEFAULT_GOAL := local

# --- from your WORKSTATION ---
sync:
	cp ../networking.nix ../routing.nix ../sysctl.nix ../nix-settings.nix ../cpu-tuning.nix ../nic-tune.nix ../nginx-anycast.nix ../firewall.nix ../bogon-refresh.nix ../monitoring.nix ./
	rsync -av --mkpath --exclude '*.2026_*' --exclude 'result' --exclude '.git' ./ das@$(HOST):/home/das/nixos/super/$(DIR)/

# Push, then flake-switch over SSH (das + passwordless sudo). NOTE: the network
# restart mid-switch may close this SSH session — cosmetic, the switch completes.
rebuild: sync
	ssh -J $(JUMP) -t das@$(HOST) 'sudo nixos-rebuild switch --flake $(FLAKE)'

# Safer remote apply: `test` activates now but does NOT set boot default, so a
# reboot reverts if it breaks connectivity. Good for risky (firewall/routing) changes.
rebuild-test: sync
	ssh -J $(JUMP) -t das@$(HOST) 'sudo nixos-rebuild test --flake $(FLAKE)'

# --- run ON the node itself (e.g. over the SOL console) --- hostname-guarded.
local: check_hostname
	sudo nixos-rebuild switch --flake $(FLAKE)

check_hostname:
ifeq ($(ACTUAL_HOSTNAME),$(EXPECTED_HOSTNAME))
	@echo "Hostnames match: $(ACTUAL_HOSTNAME)"
else
	@echo "Error: run this ON $(EXPECTED_HOSTNAME). Here it is $(ACTUAL_HOSTNAME). (Use 'make sync' / 'make rebuild' from the laptop.)"
	@exit 1
endif

build:
	nix build .#nixosConfigurations.super.config.system.build.toplevel --no-link

# DNS band-aid — run ON the node if /etc/resolv.conf has no nameservers.
dns:
	printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf

pull-hw:
	scp -o ProxyJump=$(JUMP) das@$(HOST):/etc/nixos/hardware-configuration.nix ./hardware-configuration.nix
