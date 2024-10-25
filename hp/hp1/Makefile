#
# nixos/hp1/Makefile
#
all:
	sudo cp /home/das/nixos/modules/* /etc/nixos/
	sudo cp ./*.nix /etc/nixos/
	sudo nix-channel --update
	sudo nixos-rebuild switch

sync:
	rsync -av /home/das/nixos/hp1/ hp1:/home/das/nixos/hp1/
	rsync -av /home/das/nixos/modules/ hp1:/home/das/nixos/modules/

create_cert:
# Generate private key
	openssl genrsa -out /var/lib/kubernetes/secrets/cluster-admin.pem 4096

# Generate CSR
	openssl req -new -key /var/lib/kubernetes/secrets/cluster-admin.pem -out /var/lib/kubernetes/secrets/cluster-admin.csr

# Issue certificate
	openssl ca -config ./openssl_ca_config -in /var/lib/kubernetes/secrets/cluster-admin.csr -out /var/lib/kubernetes/secrets/cluster-admin.crt -days 365 -notext -batch

# end