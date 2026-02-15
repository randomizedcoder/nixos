# MQ-CAKE test.

## Introduction

This is a design document for a test of the MQ-CAKE module that has been back ported from next-net into the 6.6.18 kernel, via mq-cake-module.nix

The system we are going to use for testing has the following ethernet NICs

```
[das@l2:~]$ lspci | grep -i eth
01:00.0 Ethernet controller: Aquantia Corp. AQtion AQC107 NBase-T/IEEE 802.3an Ethernet Controller [Atlantic 10G] (rev 02)
23:00.0 Ethernet controller: Intel Corporation Ethernet Controller X710 for 10GbE SFP+ (rev 01)
23:00.1 Ethernet controller: Intel Corporation Ethernet Controller X710 for 10GbE SFP+ (rev 01)
42:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
42:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
```


We are going to use the x2 X710 interfaces to generate load to a seperate network namespace that will have both the x2 Intel 82599ES interfaces.

So essentially the "device under test" is the network name space routing traffic over the 82599ES interfaces


```
namespace0 X710 ------> cable -----> 82599ES--\
                                               \
                                                network namespace device-under-test with routing
                                                this will be configured with different qdisc configurations, one of them being mq-cake
                                               /
namespace1 X710 ------> cable -----> 82599ES--/
```

Part of the load generation technique is to create MANY tcp flows, because a major part of this testing is to prove mq-cake is much more scalable than just normal cake.

The reason for the testing is that we want to prove that this mq-cake could be the qdisc for an upcoming confernece, where we expect to have 300-400 people connecting with phones and laptops.  Therefore we expect a large number of 5-tuple flows.

To generate load we need to use a combination of tools from nix packages:
- iperf2
- iperf3
- flent
- cursader
-

We need need to design:
1. nix pkgs.writeShellApplication to configure the namespace 0 & 1, put the X710s into them, and the network namespace and put the 82599ES interfaces into it.  We need to use the 10/8 address space.  We need scripts to configure, clear, and verify.  e.g. Ping from inside each namespace to all the others.
2. nix pkgs.writeShellApplication to configure the qdiscs on the 82599ES interfaces.  This needs to be flexiable, so that we can configure a wide range of the avilable linux qdiscs, but definitely include cake and mq-cake.
3. nix pkgs.writeShellApplication to start generating load wich each of the load generation tools.  We need a script for each tool, and then a wrapper script that could start any combinations of them, including all.
4.

