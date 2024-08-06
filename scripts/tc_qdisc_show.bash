#!/usr/bin/bash

echo tc -p -s -d qdisc show dev eno1
tc -p -s -d qdisc show dev eno1

echo tc -d class show dev eno1
tc -d class show dev eno1

echo tc -p -s -d qdisc show dev wlp3s0
tc -p -s -d qdisc show dev wlp3s0

echo tc -d class show dev wlp3s0
tc -d class show dev wlp3s0