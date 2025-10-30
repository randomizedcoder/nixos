#!/etc/profiles/per-user/das/bin/bash
#
# This script runs shellcheck on all .bash files in the scripts directory
# and reports any issues found.
#
# Exit codes:
#   0 - All scripts pass shellcheck
#   1 - One or more scripts fail shellcheck
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if shellcheck is installed
if ! command -v shellcheck >/dev/null 2>&1; then
    echo -e "${RED}Error: shellcheck is not installed${NC}"
    echo "Install with: nix-shell -p shellcheck"
    exit 1
fi

# Find all .bash files
bash_files=()
while IFS= read -r -d '' file; do
    bash_files+=("$file")
done < <(find "$SCRIPT_DIR" -name "*.bash" -type f -print0)

if [ ${#bash_files[@]} -eq 0 ]; then
    echo -e "${YELLOW}No .bash files found in $SCRIPT_DIR${NC}"
    exit 0
fi

echo -e "${YELLOW}Running shellcheck on ${#bash_files[@]} bash files...${NC}"
echo

# Track results
failed_files=()
passed_files=()

# Run shellcheck on each file
for file in "${bash_files[@]}"; do
    echo -n "Checking $(basename "$file"): "

    if shellcheck "$file"; then
        echo -e "${GREEN}PASS${NC}"
        passed_files+=("$file")
    else
        echo -e "${RED}FAIL${NC}"
        failed_files+=("$file")
    fi
done

echo
echo "=========================================="
echo -e "${GREEN}Passed: ${#passed_files[@]}${NC}"
echo -e "${RED}Failed: ${#failed_files[@]}${NC}"

if [ ${#failed_files[@]} -gt 0 ]; then
    echo
    echo -e "${RED}Failed files:${NC}"
    for file in "${failed_files[@]}"; do
        echo "  - $(basename "$file")"
    done
    exit 1
else
    echo -e "${GREEN}All scripts pass shellcheck!${NC}"
    exit 0
fi
