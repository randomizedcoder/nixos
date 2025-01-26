
# https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU
all:
	nix build .#packages.aarch64-linux.sdcard


flash:
	sudo dd if=/nix/store/z5bdj3iczgzm3qjgn6lvjswd0lmflkza-nixos-sd-image-24.11.20250119.107d5ef-aarch64-linux.img/sd-image/nixos-sd-image-24.11.20250119.107d5ef-aarch64-linux.img of=/dev/sda bs=10MB oflag=dsync status=progress

# this was copied from video: https://www.youtube.com/watch?v=6Le0IbPRzOE
# time. 53.54
# flash-to:
# 	zstdcat ./result/sd-image/nixos-sd-image-24.11.20250119.107d5ef-aarch64-linux.img.zst && \
# 		| sudo dd of=/dev/sda status=progres iflag=fullblock oflag=direct conv=fsync,noerror bs=64k