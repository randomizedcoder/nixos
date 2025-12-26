#
# nixos/hp2/Makefile
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
	sudo nix flake update;
	sudo nix-channel --update;
	sudo nixos-rebuild switch --flake .

upgrade:
	nixos-rebuild boot --flake . --upgrade

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

update_flake:
	sudo nix --extra-experimental-features nix-command --extra-experimental-features flakes flake update

sync:
	rsync -av /home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/ "${EXPECTED_HOSTNAME}":/home/das/nixos/hp/"${EXPECTED_HOSTNAME}"/

#scp hp2:/home/das/nixos/hp/hp2/flake.lock ./

updateFlake:
	scp hp2:/home/das/nixos/hp/hp2/flake.lock ./

nuke_k3s: check_hostname delete_k3s

delete k3s:
	sudo rm -rf /var/lib/rancher/k3s/ /etc/rancher/k3s
	k3s-killall.sh

# end
