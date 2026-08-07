#
# nixos/hp/hp2/Makefile
#
EXPECTED_HOSTNAME := hp2

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
	#sudo cp /home/das/nixos/modules/* /etc/nixos/
	#sudo cp ./*.nix /etc/nixos/
	#sudo nix-channel --update
	#sudo nixos-rebuild switch
	#sudo nix-channel --update;
	sudo nixos-rebuild switch --flake .
	sudo systemctl daemon-reexec

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

sync:
	rsync -avz /home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/

lock:
	scp "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/hp2/flake.lock ./

nuke_k3s: check_hostname delete_k3s

delete_k3s:
	sudo rm -rf /var/lib/rancher/k3s/ /etc/rancher/k3s
	k3s-killall.sh

systemd:
	sudo systemctl daemon-reload
	sudo systemctl stop k3s.service

# end
