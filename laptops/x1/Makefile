#
# nixos/laptops/x1/Makefile
#
EXPECTED_HOSTNAME := x1

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

#sudo nix --extra-experimental-features nix-command --extra-experimental-features flakes flake update;

rebuild_x1:
	sudo nixos-rebuild switch --flake .#x1

impure:
	sudo nixos-rebuild switch --impure --flake .

rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

rebuild_old:
	# sudo cp ./flake.nix /etc/nixos/
	# sudo cp ./flake.lock /etc/nixos/
	# sudo cp ../../modules/* /etc/nixos/
	# sudo cp ./configuration.nix /etc/nixos/
	# #sudo cp ./home-manager.nix /etc/nixos/
	# sudo cp ./home.nix /etc/nixos/
	# sudo cp ./prometheus.nix /etc/nixos/
	# sudo cp ./*.nix /etc/nixos/
	# sudo nix-channel --update
	# sudo nixos-rebuild switch
	#sudo cp ./* /etc/nixos/
	sudo nix flake update;
	#sudo nix-channel --update;
	sudo nixos-rebuild switch --flake .

update_oldm.:
	sudo nix-channel --update
	sudo nixos-rebuild switch
	#nix-shell -p vim

restart_display_manager:
	sudo systemctl restart display-manager.service

s:
	rsync -avz ./ 172.16.40.213:/home/das/nixos/laptops/x1/

copy:
	scp 172.16.40.213:/etc/nixos/*.nix ./
# end
