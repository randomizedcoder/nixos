# vm:
# 	nix-build '<nixpkgs/nixos>' -A vm -I nixpkgs=channel:nixos-24.05 -I nixos-config=./configuration.nix

# #
# buildvm:
# 	nix run .#nixosConfigurations.<hostname>.config.system.build.vm

build:
	#nixos-rebuild build-vm -I nixpkgs=channel:nixos-24.05 -I nixos-config=./configuration.nix
	nixos-rebuild build-vm -I nixos-config=./configuration.nix

# https://blog.patapon.info/nixos-local-vm/
run:
	QEMU_NET_OPTS=hostfwd=tcp::2221-:22 ./result/bin/run-vm2-vm

ssh:
	ssh root@localhost -p 2221

nographics:
	QEMU_KERNEL_PARAMS=console=ttyS0 ./result/bin/run-nixos-vm -nographic; reset

sync:
	rsync -e 'ssh -p 2221' -av --exclude 'db'  ./Downloads/xtcp/ localhost:/home/das/Downloads/xtcp/

# example
# https://github.com/nh2/nixos-vm-examples/blob/master/grub-test-vm/configuration.nix
# https://mattwidmann.net/notes/running-nixos-in-a-vm/