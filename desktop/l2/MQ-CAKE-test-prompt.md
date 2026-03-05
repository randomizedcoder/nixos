# MQ-CAKE test.

Now I would like to work on a design document for a test of the MQ-CAKE module that has been back ported from next-net into the 6.6.18 kernel, via mq-cake-module.nix

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
- maybe you can think of another tool that would be useful for generating many flows to simulate users?
- it would be nice to have some kind of DNS load test tool, becasue I would expect many DNS queries in the conference
To each tool, we want to be able to generate multiple instances of each, so that we can have concurrency within each tool, and then let the operating system provide more concurrency by running multiple instances of each process.  

We need need to design:
1. nix pkgs.writeShellApplication to configure the namespace 0 & 1, put the X710s into them, and the network namespace and put the 82599ES interfaces into it.  We need to use the 10/8 address space.  We need scripts to configure, clear, and verify.  e.g. Ping from inside each namespace to all the others.  Because The cake and cake-mq qdiscs is designed to work with flows that have at least ~20 to ~50ms latency, so on the X710 interfaces, we need to setup netem to insert latency.  Let's use 30ms for now, but we need to make this easily configurable.  It also needs some jitter, maybe 10%, configurable.  To ensure netem doesn't tail drop, we need to configure the queue length to be 100k packets (effectively unlimited)
2. nix pkgs.writeShellApplication to configure the qdiscs on the 82599ES interfaces.  This needs to be flexiable, so that we can configure a wide range of the avilable linux qdiscs, but definitely include cake and mq-cake.
3. nix pkgs.writeShellApplication to start generating load wich each of the load generation tools.  We need a script for each tool, and then a wrapper script that could start any combinations of them, including all.
4. Then we need to write a small go program that will act as the orchistrator, that will manage starting the tools, maintaining stdin, stdout, and stderr, to each of the processs.  The go code will need to be designed in a modular way, so that we have a module for reading and writing from each particular tool.  Each tool will emmit different outputs, which we will want to be able to parse in a "generic" kind of way. e.g. We will want to be able to define what strings we are looking for in a standard way, so that each module will have configuration, then when it's running each module will be looking for the configured strings.  We will need to start x2 instances of each tool to connect to each other over the loopback, so that we can capture the raw outputs and save this as testdata.  Once we have the test data, we will be able to analyze the output and work out what strings we need to match on, and what we can summarzie about the running process.  e.g. For the iperf2 & 3 we will want to be able to see how many parallal network flows, the rates, packet loss and and so on.  We will need to do this for each tool. - The go tool will need to be design with phases, so it will start of spawning instances of each tool, and then be able to increase the number of instances of each tool.  e.g. We can imagine if we want to make 500 iperf2 flows, we could start 100 with once instance, and then another 100 with another and so on.  This means we will need to carefully plan how the daemon instances that are opening listening sockets are going to use which TCP and UDP ports.  e.g. We need an allocation strategy.
5.  The go tool will also need an out loop that can then iterate through different qdiscs configured on the device-under-test network namespace.  e.g. noqueue, fq-codel, cake, cake-mq.  It will also need to able able to change the network latency, so we can teset 20ms, 30ms, 40ms, etc. - The go tool will need to use promauto to expose proemtheus metrics, like how many instances of each tool are running, how many flows, the rates, etc.

Ok, so that's some rough thoughts.  The intention will be to have a very comprhensive ability to generate traffic to simulate 300-400 people connecting with phones and laptops, and then to see the impacts of differnet qdiscs and network configurations.  We will need to consider how to monitor the solution, where the go program can obviosuly report on each tool that it is coordinating.  There is a local prometheus server, so we can configure it to gather from the go tool, and we are already collecting the node exporter metrics.  We can design a grafana dashboard to visualize what's gonig on.