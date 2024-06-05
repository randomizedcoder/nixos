#!/usr/bin/bash

echo /usr/local/bin/iperf -c 172.16.40.130 --interval 1 --time 30 -e -w 4M --tcp-write-prefetch 128K
/usr/local/bin/iperf -c 172.16.40.130 --interval 1 --time 30 -e -w 4M --tcp-write-prefetch 128K