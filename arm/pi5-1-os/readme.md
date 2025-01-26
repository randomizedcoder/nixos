

pi5-1-os is the flake that was build on the pi5

pi5-community was used to build the sd card image

https://github.com/nix-community/raspberry-pi-nix

Best comment in the issue
https://github.com/NixOS/nixpkgs/issues/260754#issuecomment-2322817130

https://nixos.wiki/wiki/NixOS_on_ARM#NixOS_installation_.26_configuration

```
sudo nixos-generate-config
```


https://nixos.wiki/wiki/NixOS_on_ARM


https://www.raspberrypi.com/documentation/computers/config_txt.html


```
[das@pi5-1:~/nixos/arm/pi5-1-os]$ sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 bs=100M oflag=dsync status=progress
1677721600 bytes (1.7 GB, 1.6 GiB) copied, 10 s, 169 MB/s
```

```
[das@pi5-1:~/nixos/arm/pi5-1-os]$ sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 bs=100M oflag=dsync status=progress
127865454592 bytes (128 GB, 119 GiB) copied, 1823 s, 70.1 MB/s
1219+1 records in
1219+1 records out
127865454592 bytes (128 GB, 119 GiB) copied, 1823.55 s, 70.1 MB/s
```