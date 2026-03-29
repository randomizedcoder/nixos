#
# nixos/laptops/chromebook/Makefile
#
# Bootstrap (run once on fresh install, before make/flakes are available):
#   sudo NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --flake .#chromebook
#
EXPECTED_HOSTNAME := chromebook

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
	sudo nixos-rebuild switch --flake .

rebuild_chromebook:
	sudo nixos-rebuild switch --flake .#chromebook

impure:
	sudo nixos-rebuild switch --impure --flake .

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

restart_display_manager:
	sudo systemctl restart display-manager.service

sync:
	rsync -avz ./ chromebook:~/nixos/laptops/chromebook/

# end
