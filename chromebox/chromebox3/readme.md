# NixOS Anywhere

## Quickstart
https://github.com/nix-community/nixos-anywhere/blob/main/docs/quickstart.md

## How to
https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/INDEX.md

https://github.com/nix-community/nixos-anywhere-examples/blob/main/disk-config.nix

https://github.com/nix-community/disko/blob/master/example/swap.nix

https://numtide.com/projects/nixos-anywhere/

https://github.com/nix-community/nixos-anywhere-examples/blob/main/flake.nix


```
das@chromebox3:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0  1.8T  0 disk
├─sda1                      8:1    0    1G  0 part /boot/efi
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0  1.8T  0 part
  ├─ubuntu--vg-ubuntu--lv 252:0    0  1.8T  0 lvm  /
  └─ubuntu--vg-lv--swap   252:1    0   32G  0 lvm  [SWAP]
```

```
das@chromebox3:~$ neofetch
            .-/+oossssoo+/-.               das@chromebox3
        `:+ssssssssssssssssss+:`           --------------
      -+ssssssssssssssssssyyssss+-         OS: Ubuntu 24.04.1 LTS x86_64
    .ossssssssssssssssssdMMMNysssso.       Host: Panther 1.0
   /ssssssssssshdmmNNmmyNMMMMhssssss/      Kernel: 6.8.0-51-generic
  +ssssssssshmydMMMMMMMNddddyssssssss+     Uptime: 23 hours, 18 mins
 /sssssssshNMMMyhhyyyyhmNMMMNhssssssss/    Packages: 774 (dpkg)
.ssssssssdMMMNhsssssssssshNMMMdssssssss.   Shell: bash 5.2.21
+sssshhhyNMMNyssssssssssssyNMMMysssssss+   Resolution: 3840x2160
ossyNMMMNyMMhsssssssssssssshmmmhssssssso   Terminal: /dev/pts/0
ossyNMMMNyMMhsssssssssssssshmmmhssssssso   CPU: Intel Celeron 2955U (2) @ 1.400GHz
+sssshhhyNMMNyssssssssssssyNMMMysssssss+   GPU: Intel Haswell-ULT
.ssssssssdMMMNhsssssssssshNMMMdssssssss.   Memory: 410MiB / 15867MiB
 /sssssssshNMMMyhhyyyyhdNMMMNhssssssss/
  +sssssssssdmydMMMMMMMMddddyssssssss+
   /ssssssssssshdmNNNNmyNMMMMhssssss/
    .ossssssssssssssssssdMMMNysssso.
      -+sssssssssssssssssyyyssss+-
        `:+ssssssssssssssssss+:`
            .-/+oossssoo+/-.
```

boot = 1G
lvm
swap = 32G
root = 100%