#
# nixos/laptops/l2/Makefile
#
EXPECTED_HOSTNAME := l2

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

rebuild_l2:
	sudo nixos-rebuild switch --flake .#l2

anywhere:
	nix run github:nix-community/nixos-anywhere -- \
		--generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
		--target-host root@172.16.40.51 \
		--flake '.#l2'

#https://nixos.org/manual/nixos/unstable/index.html#sec-nix-network-issues
#nixos-rebuild switch --option binary-caches http://my-cache.example.org/

impure:
	sudo nixos-rebuild switch --impure --flake .

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

sync:
	rsync -avz /home/das/nixos/ "${EXPECTED_HOSTNAME}":/home/das/nixos/

s:
	rsync -avz /home/das/nixos/ 172.16.40.47:/home/das/nixos/

# end
