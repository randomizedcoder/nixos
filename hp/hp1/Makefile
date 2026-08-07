#
# nixos/hp/hp1/Makefile
#
EXPECTED_HOSTNAME := hp1

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

update:
	sudo nix flake update;

# sync — rsync this host's config to the target.
#
# IMPORTANT: the .git/ directory MUST be synced too. This repo uses
# `nix flake` / `nixos-rebuild --flake` on the target, and Nix flake
# source resolution walks up to the nearest .git/ and uses only
# git-tracked files when staging the source into /nix/store. A
# nixos-rebuild on the target without an up-to-date .git/ will:
#   - silently skip any newly-added files (Nix can't see them)
#   - fail with "path '/nix/store/.../hp/<host>/<file>' does not
#     exist" if configuration.nix imports a file that's on disk but
#     untracked in the target's local git index
#
# We sync only THIS host's subdir + .git/, not the other hosts'
# subdirs, to keep the per-host blast radius small. `git status` on
# the target will report other hosts' files as deleted — that's
# expected and harmless because nothing on this host references them.
sync:
	rsync -avz /home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/
	rsync -avz /home/das/nixos/.git/ "${EXPECTED_HOSTNAME}":/home/das/nixos/.git/

lock:
	scp "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/hp1/flake.lock ./

# end
