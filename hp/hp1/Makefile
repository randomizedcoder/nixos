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

sync:
	rsync -avz /home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/

lock:
	scp "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/hp1/flake.lock ./

# end
