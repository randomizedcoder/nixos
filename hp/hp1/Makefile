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
	#sudo cp /home/das/nixos/modules/* /etc/nixos/
	#sudo cp ./*.nix /etc/nixos/
	#sudo nix-channel --update
	#sudo nixos-rebuild switch
	#sudo nix-channel --update;
	sudo nixos-rebuild switch --flake .
	#sudo systemctl restart ffmpeg-stream

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
	#rsync -av /home/das/nixos/modules/ hp1:/home/das/nixos/modules/

updateFlake:
	scp hp1:/home/das/nixos/hp/hp1/flake.lock ./

# https://nixos.wiki/wiki/Kubernetes#reset_to_a_clean_state
nuke_k8s: check_hostname delete_k8s

delete_k8s:
	sudo rm -rf /var/lib/kubernetes/ /var/lib/etcd/ /var/lib/cfssl/ /var/lib/kubelet/
	sudo rm -rf /etc/kube-flannel/ /etc/kubernetes/

nuke_k3s: check_hostname delete_k3s

delete k3s:
	sudo rm -rf /var/lib/rancher/k3s/ /etc/rancher/k3s
	k3s-killall.sh

create_cert:
# Generate private key
	openssl genrsa -out /var/lib/kubernetes/secrets/cluster-admin.pem 4096

# Generate CSR
	openssl req -new -key /var/lib/kubernetes/secrets/cluster-admin.pem -out /var/lib/kubernetes/secrets/cluster-admin.csr

# Issue certificate
	openssl ca -config ./openssl_ca_config -in /var/lib/kubernetes/secrets/cluster-admin.csr -out /var/lib/kubernetes/secrets/cluster-admin.crt -days 365 -notext -batch



# end
