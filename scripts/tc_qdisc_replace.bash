#!/usr/bin/bash

# https://www.man7.org/linux/man-pages/man8/tc-fq_codel.8.html

echo tc qdisc replace dev eno1 root fq_codel ce_threshold 1ms ce_threshold_selector 0x1/0x3
tc qdisc replace dev eno1 root fq_codel ce_threshold 1ms ce_threshold_selector 0x1/0x3

echo tc qdisc replace dev wlp3s0 root fq_codel ce_threshold 1ms ce_threshold_selector 0x1/0x3
tc qdisc replace dev wlp3s0 root fq_codel ce_threshold 1ms ce_threshold_selector 0x1/0x3
