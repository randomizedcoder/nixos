#
# nixos/hp/hp3/Makefile
#
EXPECTED_HOSTNAME := hp3

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
	sudo systemctl daemon-reexec

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

# Bootstrap target for a freshly-installed NixOS host where
# experimental-features (nix-command, flakes) isn't enabled yet in
# /etc/nix/nix.conf. Use `boot` rather than `switch` because the xdp2
# physical-testbed module sets kernel cmdline (isolcpus, mitigations=off,
# hugepages, nohz_full, rcu_nocbs) — those only apply after a reboot.
# After this lands once, the NixOS-managed nix.conf carries the flag
# and subsequent rebuilds can use plain `make`.
#
# Note: nixos-rebuild itself doesn't accept --extra-experimental-features
# (that's a `nix` flag). Use --option to forward it through.
bootstrap:
	sudo nixos-rebuild boot \
	  --option experimental-features 'nix-command flakes' \
	  --flake .#hp3
	@echo
	@echo "bootstrap complete — reboot with: sudo reboot"

# Like bootstrap but switches instead of boots — only safe if you've
# already booted into the new kernel via `make bootstrap && reboot`.
bootstrap_switch:
	sudo nixos-rebuild switch \
	  --option experimental-features 'nix-command flakes' \
	  --flake .#hp3

update:
	sudo nix flake update;

# Same as `update` but with the experimental-features flag for a
# pre-bootstrap host. Once the system has been rebuilt once, use
# `make update`.
bootstrap_update:
	sudo nix --extra-experimental-features 'nix-command flakes' flake update

sync:
	rsync -avz /home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/

lock:
	scp "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/hp3/flake.lock ./

# end
