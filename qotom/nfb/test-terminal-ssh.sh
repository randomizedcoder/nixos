#!/usr/bin/env bash
# Terminal and SSH Diagnostic Script
# Run this on your client machine (l)

set -e

echo "=== Terminal Diagnostic Tests ==="
echo

# Test 1: Terminal Info
echo "1. Terminal Information:"
echo "   TERM=$TERM"
echo "   COLORTERM=${COLORTERM:-not set}"
echo "   TERM_PROGRAM=${TERM_PROGRAM:-not set}"
echo "   Terminal: $(tput longname 2>/dev/null || echo 'unknown')"
echo

# Test 2: Local Terminal Rendering Speed
echo "2. Testing local terminal rendering:"
echo -n "   Immediate output test... "
sleep 0.1
echo "✓ Pass"
echo

# Test 3: SSH Connection Timing (without TTY)
echo "3. Testing SSH connection speed (no TTY):"
time ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
  172.16.40.185 'echo "Connection test"' 2>&1 | grep -v "^Warning:" || true
echo

# Test 4: SSH Connection Timing (with TTY)
echo "4. Testing SSH connection speed (with TTY):"
time ssh -tt 172.16.40.185 'echo "TTY test"; exit' 2>&1 | head -3
echo

# Test 5: Test prompt delay
echo "5. Testing SSH prompt delay:"
echo "   Connecting and measuring time to prompt..."
(
  timeout 10 ssh -o ConnectTimeout=5 172.16.40.185 <<'REMOTE'
    echo "Remote shell started"
    sleep 0.5
    echo "Ready"
REMOTE
) 2>&1 | while IFS= read -r line; do
  echo "   [$(date +%H:%M:%S.%N | cut -b1-12)] $line"
done
echo

# Test 6: Terminal Control Sequences
echo "6. Testing terminal control sequences:"
printf "   \033[2J\033[H"  # Clear screen
printf "   \033[32mGreen text test\033[0m\n"
echo "   If colors work above, terminal control sequences are OK"
echo

# Test 7: Check for buffering issues
echo "7. Testing output buffering:"
echo -n "   Line 1 (no newline)... "
sleep 0.2
echo "Line 2 (with newline)"
echo

# Test 8: SSH multiplexing status
echo "8. SSH Multiplexing Status:"
if [ -S ~/.ssh/master-das@172.16.40.185:22 ]; then
  echo "   Master socket exists: ~/.ssh/master-das@172.16.40.185:22"
  ls -lh ~/.ssh/master-das@172.16.40.185:22 2>/dev/null || echo "   (socket exists but may be stale)"
else
  echo "   No master socket found (multiplexing not active)"
fi
echo

echo "=== Diagnostic Complete ==="
echo
echo "Recommendations:"
echo "  - If Test 4 is slow (>2 seconds), the issue is server-side"
echo "  - If Tests 3-4 are fast but interactive SSH is slow, it's terminal buffering"
echo "  - Try different terminals: xterm, alacritty, kitty, gnome-terminal"
echo "  - For Ghostty specifically, try: ssh -o RequestTTY=force ..."

