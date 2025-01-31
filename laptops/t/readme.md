# readme


## Nvidia nightmare

Big thread, with feedback about my issue
https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/25



https://github.com/elFarto/nvidia-vaapi-driver/issues/311

```
[das@t:~/Downloads/nixpkgs]$ ls -la /dev/dri/
total 0
drwxr-xr-x   3 root root        140 Jan 30 22:16 .
drwxr-xr-x  20 root root       4080 Jan 31 07:24 ..
drwxr-xr-x   2 root root        120 Jan 30 22:16 by-path
crw-rw----+  1 root video  226,   1 Jan 31 07:24 card1
crw-rw----+  1 root video  226,   2 Jan 30 22:16 card2
crw-rw-rw-   1 root render 226, 128 Jan 30 22:16 renderD128
crw-rw-rw-   1 root render 226, 129 Jan 30 22:16 renderD129

[das@t:~/Downloads/nixpkgs]$ ls -la /dev/dri/by-path/
total 0
drwxr-xr-x 2 root root 120 Jan 30 22:16 .
drwxr-xr-x 3 root root 140 Jan 30 22:16 ..
lrwxrwxrwx 1 root root   8 Jan 30 22:16 pci-0000:00:02.0-card -> ../card2
lrwxrwxrwx 1 root root  13 Jan 30 22:16 pci-0000:00:02.0-render -> ../renderD129
lrwxrwxrwx 1 root root   8 Jan 30 22:16 pci-0000:01:00.0-card -> ../card1
lrwxrwxrwx 1 root root  13 Jan 30 22:16 pci-0000:01:00.0-render -> ../renderD128

[das@t:~/Downloads/nixpkgs]$ lspci | grep VGA
00:02.0 VGA compatible controller: Intel Corporation CometLake-H GT2 [UHD Graphics] (rev 05)
01:00.0 VGA compatible controller: NVIDIA Corporation TU117GLM [Quadro T2000 Mobile / Max-Q] (rev a1)
```