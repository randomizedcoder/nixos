init:
	nix flake init -t github:astro/microvm.nix

show:
	nix flake show

run:
	nix run microvm#build-microvm

buildd:
	nix build '.#dockerImage'