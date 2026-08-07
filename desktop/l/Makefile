#
# nixos/laptops/l/Makefile
#
EXPECTED_HOSTNAME := l

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

# Build without installing (no root required)
build:
	nix build .#nixosConfigurations.$(EXPECTED_HOSTNAME).config.system.build.toplevel --no-link

# Build with output link in ./result
build-link:
	nix build .#nixosConfigurations.$(EXPECTED_HOSTNAME).config.system.build.toplevel

rebuild_l:
	sudo nixos-rebuild switch --flake .#t

#https://nixos.org/manual/nixos/unstable/index.html#sec-nix-network-issues
#nixos-rebuild switch --option binary-caches http://my-cache.example.org/

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

#ls -l /run/opengl-driver/lib/gbm/
#readlink /run/opengl-driver/lib/gbm/dri_gbm.so
#glxinfo | grep -i 'renderer'

#journalctl -b | grep -Ei 'X.*fatal|gdm|wayland|mesa|amdgpu' --no-pager
#less /var/log/Xorg.0.log

#nix-shell -p mesa-demos
#glxinfo | grep -i opengl

# cat configuration.nix | grep -A 20 "hardware.graphics ="

# end
