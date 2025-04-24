
https://www.youtube.com/watch?v=VIuPRL6Ucgk

https://wiki.nixos.org/wiki/NixOS_on_ARM/Building_Images#Compiling_through_binfmt_QEMU

https://github.com/jason-m/whydoesnothing.work/tree/main/episode-5

```
[das@t:~/nixos/arm/pi5-1]$ wget -O flake.nix https://raw.githubusercontent.com/jason-m/whydoesnothing.work/refs/heads/main/episode-5/flake.nix
--2025-01-21 06:15:44--  https://raw.githubusercontent.com/jason-m/whydoesnothing.work/refs/heads/main/episode-5/flake.nix
Resolving raw.githubusercontent.com (raw.githubusercontent.com)... 2606:50c0:8002::154, 2606:50c0:8001::154, 2606:50c0:8000::154, ...
Connecting to raw.githubusercontent.com (raw.githubusercontent.com)|2606:50c0:8002::154|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 964 [text/plain]
Saving to: ‘flake.nix’

flake.nix                                       100%[======================================================================================================>]     964  --.-KB/s    in 0s

2025-01-21 06:15:44 (29.1 MB/s) - ‘flake.nix’ saved [964/964]


[das@t:~/nixos/arm/pi5-1]$ wget -O extra-config.nix https://raw.githubusercontent.com/jason-m/whydoesnothing.work/refs/heads/main/episode-5/extra-config.nix
--2025-01-21 06:16:06--  https://raw.githubusercontent.com/jason-m/whydoesnothing.work/refs/heads/main/episode-5/extra-config.nix
Resolving raw.githubusercontent.com (raw.githubusercontent.com)... 2606:50c0:8003::154, 2606:50c0:8002::154, 2606:50c0:8001::154, ...
Connecting to raw.githubusercontent.com (raw.githubusercontent.com)|2606:50c0:8003::154|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 213 [text/plain]
Saving to: ‘extra-config.nix’

extra-config.nix                                100%[======================================================================================================>]     213  --.-KB/s    in 0s

2025-01-21 06:16:06 (2.43 MB/s) - ‘extra-config.nix’ saved [213/213]
```

```
[das@t:~/nixos/arm/pi5-1]$ sudo dd if=/nix/store/z5bdj3iczgzm3qjgn6lvjswd0lmflkza-nixos-sd-image-24.11.20250119.107d5ef-aarch64-linux.img/sd-image/nixos-sd-image-24.11.20250119.107d5ef-aarch64-linux.img of=/dev/sda bs=10MB oflag=dsync status=progress
90000000 bytes (90 MB, 86 MiB) copied, 6 s, 14.4 MB/s
```

```
[das@t:~/nixos/arm/pi5-1]$ sudo fdisk -l /dev/sda
[sudo] password for das:
Disk /dev/sda: 29.73 GiB, 31927042048 bytes, 62357504 sectors
Disk model: Multi-Card
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x2178694e

Device     Boot Start     End Sectors  Size Id Type
/dev/sda1       16384   77823   61440   30M  b W95 FAT32
/dev/sda2  *    77824 4642695 4564872  2.2G 83 Linux
```


```
[das@t:~/nixos/arm/pi5-1]$ sudo tar cfz sda2.tar.gz /run/media/das/NIXOS_SD
[sudo] password for das:
tar: Removing leading `/' from member names
tar: Removing leading `/' from hard link targets

[das@t:~/nixos/arm/pi5-1]$ sudo tar cfz sda1.tar.gz /run/media/das/FIRMWARE
tar: Removing leading `/' from member names

[das@t:~/nixos/arm/pi5-1]$ ls -la
total 1002700
drwxr-xr-x 2 das users       4096 Jan 21 13:38 .
drwxr-xr-x 3 das users       4096 Jan 21 06:15 ..
-rw-r--r-- 1 das users        209 Jan 21 06:21 extra-config.nix
-rw-r--r-- 1 das users       1566 Jan 21 06:23 flake.lock
-rw-r--r-- 1 das users       1237 Jan 21 08:51 flake.nix
-rw-r--r-- 1 das users        662 Jan 21 08:59 Makefile
-rw-r--r-- 1 das users       2278 Jan 21 08:58 readme.md
lrwxrwxrwx 1 das users         99 Jan 21 08:55 result -> /nix/store/z5bdj3iczgzm3qjgn6lvjswd0lmflkza-nixos-sd-image-24.11.20250119.107d5ef-aarch64-linux.img
-rw-r--r-- 1 das users   13499760 Jan 21 13:44 sda1.tar.gz
-rw-r--r-- 1 das users 1013224749 Jan 21 13:44 sda2.tar.gz
```




https://discourse.nixos.org/t/cross-compiling-building-a-flake-for-raspberry-pi-taking-too-long/51951/2


https://nixos-and-flakes.thiscute.world/development/cross-platform-compilation


https://nixos-and-flakes.thiscute.world/development/cross-platform-compilation#cross-compilation