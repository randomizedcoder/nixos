#
# nixos/chromebox/chromebox1/Makefile
#
EXPECTED_HOSTNAME := chromebox1

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
	sudo nix flake update;
	sudo nixos-rebuild switch --flake .

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

# Bootstrap target for a freshly-installed NixOS host where
# experimental-features (nix-command, flakes) isn't enabled yet in
# /etc/nix/nix.conf. Use `boot` rather than `switch` because the xdp2
# physical-testbed module sets kernel cmdline (mitigations=off,
# hugepages, processor.max_cstate=1) — those only apply after a reboot.
#
# Note: nixos-rebuild itself doesn't accept --extra-experimental-features
# (that's a `nix` flag). Use --option to forward it through.
bootstrap:
	sudo nixos-rebuild boot \
	  --option experimental-features 'nix-command flakes' \
	  --flake .#chromebox1
	@echo
	@echo "bootstrap complete — reboot with: sudo reboot"

bootstrap_switch:
	sudo nixos-rebuild switch \
	  --option experimental-features 'nix-command flakes' \
	  --flake .#chromebox1

bootstrap_update:
	sudo nix --extra-experimental-features 'nix-command flakes' flake update

# nixos-anywhere re-install (wipes disk via disko). Use with care.
anywhere:
	nix run github:nix-community/nixos-anywhere -- --flake '.#chromebox1' --target-host root@chromebox1
# Legacy form (pre-rename, when chromebox1 lived at .179 before the
# 2026-06-02 re-install / DHCP lease change to .178). Kept for reference.
#anywhere_legacy:
#	nix run github:nix-community/nixos-anywhere -- --flake '.#chromebox1' --target-host root@172.16.40.179

gen_hardware:
	nix run github:numtide/nixos-anywhere -- -f '.#chromebox1' --generate-hardware-config nixos-generate-config ./hardware-configuration.nix --target-host root@chromebox1

vmtest:
	sudo nix flake update;
	sudo nix flake lock;
	nix run github:numtide/nixos-anywhere -- -f '.#chromebox1' --vm-test

sync:
	rsync -avz /home/das/nixos/chromebox/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/chromebox/"${EXPECTED_HOSTNAME}"/

lock:
	scp "${EXPECTED_HOSTNAME}":/home/das/nixos/chromebox/chromebox1/flake.lock ./

# end
