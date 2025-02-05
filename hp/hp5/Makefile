#
# nixos/hp/hp5/Makefile
#
EXPECTED_HOSTNAME := hp5

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
	sudo systemctl restart create-stream-sdp.service
	sudo systemctl restart create-stream-m3u8.service
	sudo systemctl restart ffmpeg-hls


rebuild_trace:
	sudo nixos-rebuild switch --show-trace --flake .

update:
	sudo nix flake update;

sync:
	rsync -av /home/das/nixos/hp/hp5/ hp5:/home/das/nixos/hp/hp5/
	#rsync -av /home/das/nixos/modules/ hp5:/home/das/nixos/modules/

nuke_k3s: check_hostname delete_k3s

delete k3s:
	sudo rm -rf /var/lib/rancher/k3s/ /etc/rancher/k3s
	k3s-killall.shs

systemd:
	sudo systemctl daemon-reload
	sudo systemctl stop k3s.service

# end
