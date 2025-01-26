
build:
	nix --experimental-features 'nix-command flakes' build '.#nixosConfigurations.myrpi5.config.system.build.sdImage'
	#nix build '.#nixosConfigurations.myrpi5.config.system.build.sdImage'

dd_to_sd:
	zstdcat ./nixos-sd-image-24.11.20250120.ae584d9-aarch64-linux.img.zst | dd of=/dev/sda bs=10MB oflag=dsync status=progress
