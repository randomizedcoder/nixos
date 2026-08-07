#
# nixos/laptops/t/Makefile
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
	sudo nixos-rebuild switch --flake .

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

# Bootstrap target for a host where the existing /etc/nix/nix.conf
# doesn't yet include the xdp2 flake input (post-rewrite first run)
# or where you've blown away flake.lock and want to rebuild fresh.
# `boot` rather than `switch` because the xdp2 physical-testbed module
# sets kernel cmdline (mitigations=off, hugepages, isolcpus, nohz_full,
# rcu_nocbs, processor.max_cstate=1) — those only apply after reboot.
#
# Note: nixos-rebuild itself doesn't accept --extra-experimental-features
# (that's a `nix` flag). Use --option to forward it through.
bootstrap:
	sudo nixos-rebuild boot \
	  --option experimental-features 'nix-command flakes' \
	  --flake .#t
	@echo
	@echo "bootstrap complete — reboot with: sudo reboot"

bootstrap_switch:
	sudo nixos-rebuild switch \
	  --option experimental-features 'nix-command flakes' \
	  --flake .#t

bootstrap_update:
	sudo nix --extra-experimental-features 'nix-command flakes' flake update

# sync — rsync this host's config to the target.
#
# IMPORTANT: the .git/ directory MUST be synced too. This repo uses
# `nix flake` / `nixos-rebuild --flake` on the target, and Nix flake
# source resolution walks up to the nearest .git/ and uses only
# git-tracked files when staging the source into /nix/store. A
# nixos-rebuild on the target without an up-to-date .git/ will:
#   - silently skip any newly-added files (Nix can't see them)
#   - fail with "path '/nix/store/.../laptops/<host>/<file>' does not
#     exist" if configuration.nix imports a file that's on disk but
#     untracked in the target's local git index
#
# We sync only THIS host's subdir + .git/, not the other hosts'
# subdirs, to keep the per-host blast radius small. `git status` on
# the target will report other hosts' files as deleted — that's
# expected and harmless because nothing on this host references them.
sync:
	rsync -avz /home/das/nixos/laptops/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/laptops/"${EXPECTED_HOSTNAME}"/
	rsync -avz /home/das/nixos/.git/ "${EXPECTED_HOSTNAME}":/home/das/nixos/.git/

lock:
	scp "${EXPECTED_HOSTNAME}":/home/das/nixos/laptops/t/flake.lock ./

# end
