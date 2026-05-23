#
# nixos/laptops/d/Makefile
#
EXPECTED_HOSTNAME := d

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

# One-time bootstrap rebuild on a fresh NixOS install where flakes are not yet
# enabled in /etc/nix/nix.conf. After this completes, the flake's nix.settings
# turns flakes on permanently and plain `make rebuild` works thereafter.
rebuild_first:
	sudo nixos-rebuild switch --flake .#d \
		--option experimental-features "nix-command flakes"

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

sync:
	rsync -avz ./ d:~/nixos/laptops/d/

lock:
	scp d:~/nixos/laptops/d/flake.lock ./

# end
