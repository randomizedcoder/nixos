

https://github.com/astro/microvm.nix/blob/main/examples/microvms-host.nix

https://raw.githubusercontent.com/astro/microvm.nix/refs/heads/main/examples/microvms-host.nix

Run by doing

nix run microvm#vm

 591250 pts/2    Sl+    1:49 microvm@microvms-host -name microvms-host -M microvm,accel=kvm:tcg,acpi=on,mem-merge=on,pcie=off,pic=off,pit=off,usb=off -m 8192 -smp 4 -nodefaults -no-user-config -no-reboot -kernel /nix/store/fl3kawlpdcc1cyr89fdc6nb1nb1g2lcm-linux-6.6.48/bzImage -initrd /nix/store/hx09sq2r4ajkj37ap1lxz1bwcfam4mq3-initrd-linux-6.6.48/initrd -chardev stdio,id=stdio,signal=off -device virtio-rng-device -serial chardev:stdio -enable-kvm -cpu host,+x2apic,-sgx -device i8042 -append earlyprintk=ttyS0 console=ttyS0 reboot=t panic=-1 root=fstab loglevel=4 init=/nix/store/qj8qyz371lyjkzwidp1xw9h3mcn1fvqk-nixos-system-microvms-host-24.11.20240904.ad416d0/init regInfo=/nix/store/6dp4kp23rzq1agw783nnryqp1phhnjgv-closure-info/registration -drive id=store,format=raw,read-only=on,file=/nix/store/xcawgx7h66zpm0xrh5myrkx6p3wwq6lh-microvm-store-disk.erofs,if=none,aio=io_uring -device virtio-blk-device,drive=store -nographic -sandbox on -qmp unix:microvms-host.sock,server,nowait -netdev user,id=qemu -device virtio-net-device,netdev=qemu,mac=02:00:00:01:01:01

