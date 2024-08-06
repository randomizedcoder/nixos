init:
	nix flake init -t github:astro/microvm.nix

show:
	nix flake show

update:
	nix flake update . --commit-lock-file

run:
	nix run microvm#microvm-qemu-my-microvm

runSimple:
	nix run .#my-microvm

runVM:
	microvm -u my-microvm

buildd:
	nix build '.#dockerImage'