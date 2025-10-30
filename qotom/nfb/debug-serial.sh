#!/etc/profiles/per-user/das/bin/bashervice 
# Debug script for serial console on ttyS0

echo "=== Serial Console Debug Info ==="
echo "Date: $(date)"
echo

echo "1. Kernel command line:"
cat /proc/cmdline | grep -o 'console=[^ ]*'
echo

echo "2. Serial port info:"
if command -v setserial >/dev/null 2>&1; then
    setserial -g /dev/ttyS[0-3] 2>/dev/null || echo "setserial not available"
else
    echo "setserial not installed (install with: nix-env -iA nixos.setserial)"
fi
echo

echo "3. Current ttyS0 settings:"
stty -F /dev/ttyS0 -a 2>/dev/null || echo "Cannot read ttyS0 settings"
echo

echo "4. Serial getty service status:"
systemctl status serial-getty@ttyS0 --no-pager
echo

echo "5. Recent serial getty logs:"
journalctl -u serial-getty@ttyS0 --since "5 minutes ago" --no-pager
echo

echo "6. Kernel messages about serial:"
dmesg | grep -i 'ttyS\|serial' | tail -10
echo

echo "7. Available serial devices:"
ls -la /dev/ttyS* 2>/dev/null || echo "No ttyS devices found"
echo

echo "8. Test: Sending 'hello' to ttyS0 (press Ctrl+C to stop):"
echo "Type 'hello' and press Enter, then check your serial client"
echo "Press Ctrl+C to stop this test"
timeout 10s cat /dev/ttyS0 &
CAT_PID=$!
echo "hello" > /dev/ttyS0
sleep 2
kill $CAT_PID 2>/dev/null
echo "Test complete"
