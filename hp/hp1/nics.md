[das@hp1:~]$ ls -l /sys/class/net/*/device
lrwxrwxrwx 1 root root 0 Nov 21 12:43 /sys/class/net/eno1/device -> ../../../0000:06:00.0
lrwxrwxrwx 1 root root 0 Nov 21 12:43 /sys/class/net/enp1s0f0/device -> ../../../0000:01:00.0
lrwxrwxrwx 1 root root 0 Nov 21 12:43 /sys/class/net/enp1s0f1/device -> ../../../0000:01:00.1
lrwxrwxrwx 1 root root 0 Nov 21 12:43 /sys/class/net/enp4s0f0/device -> ../../../0000:04:00.0
lrwxrwxrwx 1 root root 0 Nov 21 12:43 /sys/class/net/enp4s0f1/device -> ../../../0000:04:00.1

[das@hp1:~]$ lspci | grep -i ethernet
01:00.0 Ethernet controller: Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
01:00.1 Ethernet controller: Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
04:00.0 Ethernet controller: Intel Corporation 82571EB/82571GB Gigabit Ethernet Controller D0/D1 (copper applications) (rev 06)
04:00.1 Ethernet controller: Intel Corporation 82571EB/82571GB Gigabit Ethernet Controller D0/D1 (copper applications) (rev 06)
06:00.0 Ethernet controller: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller (rev 0e)

[das@hp1:~]$ ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
    link/ether 10:e7:c6:b6:6e:e2 brd ff:ff:ff:ff:ff:ff
    altname enp6s0f0
    altname enx10e7c6b66ee2
3: enp4s0f0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN mode DEFAULT group default qlen 1000
    link/ether 98:b7:85:01:ff:06 brd ff:ff:ff:ff:ff:ff
    altname enx98b78501ff06
4: enp4s0f1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN mode DEFAULT group default qlen 1000
    link/ether 98:b7:85:01:ff:07 brd ff:ff:ff:ff:ff:ff
    altname enx98b78501ff07
5: enp1s0f0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN mode DEFAULT group default qlen 1000
    link/ether a0:36:9f:44:04:c8 brd ff:ff:ff:ff:ff:ff
    altname enxa0369f4404c8
6: enp1s0f1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN mode DEFAULT group default qlen 1000
    link/ether a0:36:9f:44:04:ca brd ff:ff:ff:ff:ff:ff
    altname enxa0369f4404ca

[das@hp1:~]$

