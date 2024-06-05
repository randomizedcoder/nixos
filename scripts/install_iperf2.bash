#!/usr/bin/bash

wget https://sourceforge.net/projects/iperf2/files/iperf-2.2.0.tar.gz/download
mv ./download ./iperf-2.2.0.tar.gz

tar zxf ./iperf-2.2.0.tar.gz
cd iperf-2.2.0 || exit

# git clone https://git.code.sf.net/p/iperf2/code iperf2-code
# cd iperf2-code || exit
./configure
make
echo "sudo make install"