#!/usr/bin/bash
#
# This script pins iwlwifi and enp1 to cores 0-1
#
# https://www.kernel.org/doc/Documentation/IRQ-affinity.txt
# https://linux-kernel-labs.github.io/refs/heads/master/lectures/interrupts.html#interrupt-handling-in-linux
# in future consider
# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/performance_tuning_guide/network-rps

# [das@hp0:~]$ cat /proc/interrupts | grep wifi
#   86:          0          0          0    4361163          0          0          0          0  IR-PCI-MSIX-0000:03:00.0    0-edge      iwlwifi:default_queue
#   87:     527141          0          0          0          0          0          0          0  IR-PCI-MSIX-0000:03:00.0    1-edge      iwlwifi:queue_1
#   88:          0      36601          0          0          0          0          0          0  IR-PCI-MSIX-0000:03:00.0    2-edge      iwlwifi:queue_2
#   89:          0          0     549109          0          0          0          0          0  IR-PCI-MSIX-0000:03:00.0    3-edge      iwlwifi:queue_3
#   90:          0          0          0     393223          0          0          0          0  IR-PCI-MSIX-0000:03:00.0    4-edge      iwlwifi:queue_4
#   91:          0          0          0          0    1776763          0          0          0  IR-PCI-MSIX-0000:03:00.0    5-edge      iwlwifi:queue_5
#   92:          0          0          0          0          0     159677          0          0  IR-PCI-MSIX-0000:03:00.0    6-edge      iwlwifi:queue_6
#   93:          0          0          0          0          0          0     295033          0  IR-PCI-MSIX-0000:03:00.0    7-edge      iwlwifi:queue_7
#   94:          0          0          0          0          0          0          0     642178  IR-PCI-MSIX-0000:03:00.0    8-edge      iwlwifi:queue_8
#   95:          0          0          0          0          3          0          0          0  IR-PCI-MSIX-0000:03:00.0    9-edge      iwlwifi:exception
# grep iwlwifi /proc/interrupts | awk '{ print $1 }' | sed -e 's/://'

CORES="0-3"

echo "starting to pin"
echo "BEFORE"
echo "grep iwlwifi /proc/interrupts"
grep iwlwifi /proc/interrupts

for i in {86..95}
do
  echo "Loop:${i}"
  echo "echo ${CORES} > /proc/irq/${i}/smp_affinity_list"
  echo "${CORES}" > /proc/irq/"${i}"/smp_affinity_list
  echo "cat /proc/irq/${i}/smp_affinity_list"
  cat /proc/irq/"${i}"/smp_affinity_list
done

echo "AFTER"
echo "grep iwlwifi /proc/interrupts"
grep iwlwifi /proc/interrupts

#[das@hp0:~]$ grep eno /proc/interrupts
#  83:          0          0          0          0          0          0          0          0  IR-PCI-MSIX-0000:05:00.0    0-edge      eno1

echo "echo ${CORES} > /proc/irq/83/smp_affinity_list"
echo "${CORES}" > /proc/irq/83/smp_affinity_list
