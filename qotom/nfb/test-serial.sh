#!/etc/profiles/per-user/das/bin/bash
# Test script for serial communication between ttyS0 and ttyUSB0

echo "=== Serial Communication Test ==="
echo "Date: $(date)"
echo

# Check if we have both devices
if [ ! -e /dev/ttyS0 ]; then
    echo "ERROR: /dev/ttyS0 not found"
    exit 1
fi

if [ ! -e /dev/ttyUSB0 ]; then
    echo "ERROR: /dev/ttyUSB0 not found"
    exit 1
fi

echo "1. Available serial devices:"
ls -la /dev/ttyS* /dev/ttyUSB*
echo

echo "2. Current ttyS0 settings:"
stty -F /dev/ttyS0 -a 2>/dev/null || echo "Cannot read ttyS0 settings"
echo

echo "3. Current ttyUSB0 settings:"
stty -F /dev/ttyUSB0 -a 2>/dev/null || echo "Cannot read ttyUSB0 settings"
echo

echo "4. Setting up ttyUSB0 for testing (115200 8N1):"
sudo stty -F /dev/ttyUSB0 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts -echo
echo "ttyUSB0 configured for 115200 8N1"
echo

echo "5. Test 1: Send data from ttyS0 to ttyUSB0"
echo "   - In another terminal, run: sudo cat /dev/ttyUSB0"
echo "   - Press Enter to send 'hello' from ttyS0"
read -p "   Press Enter to continue..."
echo "hello from ttyS0" | sudo tee /dev/ttyS0
echo "   Data sent to ttyS0"
echo

echo "6. Test 2: Send data from ttyUSB0 to ttyS0"
echo "   - In another terminal, run: sudo cat /dev/ttyS0"
echo "   - Press Enter to send 'hello' from ttyUSB0"
read -p "   Press Enter to continue..."
echo "hello from ttyUSB0" | sudo tee /dev/ttyUSB0
echo "   Data sent to ttyUSB0"
echo

echo "7. Test 3: Interactive test"
echo "   - Connect a null modem cable between ttyS0 and ttyUSB0"
echo "   - In another terminal, run: sudo minicom -D /dev/ttyUSB0 -b 115200"
echo "   - Press Enter to start listening on ttyS0"
read -p "   Press Enter to continue..."
echo "   Listening on ttyS0... (Press Ctrl+C to stop)"
timeout 10s sudo cat /dev/ttyS0 &
CAT_PID=$!
sleep 2
echo "test message" | sudo tee /dev/ttyUSB0
sleep 3
kill $CAT_PID 2>/dev/null
echo "   Test complete"
echo

echo "8. Test 4: Check agetty process"
echo "   Current agetty processes:"
ps ax | grep agetty | grep -v grep
echo

echo "=== Test Complete ==="
echo "If you see data flowing between the devices, the serial console is working!"
echo "If not, check:"
echo "  - Cable connections"
echo "  - Baud rate settings (should be 115200 8N1)"
echo "  - Flow control settings"
