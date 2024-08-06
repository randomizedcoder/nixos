vm:
	nix-build '<nixpkgs/nixos>' -A vm -I nixpkgs=channel:nixos-24.05 -I nixos-config=./configuration.nix

#
buildvm:
	nix run .#nixosConfigurations.<hostname>.config.system.build.vm

build:
	nixos-rebuild build-vm -I nixos-config=./configuration.nix

# https://blog.patapon.info/nixos-local-vm/
ssh:
	QEMU_NET_OPTS=hostfwd=tcp::2221-:22 ./result/bin/run-vm1-vm
	ssh root@localhost -p 2221

nographics:
	QEMU_KERNEL_PARAMS=console=ttyS0 ./result/bin/run-nixos-vm -nographic; reset