#!/bin/bash
# Check cycles balance for a canister
# Input: canister name, network
# Output: cycles in TC (trillion cycles), "local", or "unknown"

set -euo pipefail

CANISTER=${1:-}
NETWORK=${2:-local}

if [ -z "$CANISTER" ]; then
    echo "Usage: cycles-check.sh <canister_name> [network]"
    echo "  network: local (default) or ic"
    exit 1
fi

# Check if dfx is installed
if ! command -v dfx &>/dev/null; then
    echo "error: dfx not installed"
    exit 1
fi

# Local network doesn't have real cycles
if [ "$NETWORK" = "local" ]; then
    echo "local"
    exit 0
fi

# Get canister status and extract cycles balance
STATUS_OUTPUT=$(dfx canister status "$CANISTER" --network "$NETWORK" 2>&1) || {
    echo "unknown"
    exit 0
}

# Parse cycles from status output
# Format varies: "Balance: 1_234_567_890_123 Cycles" or similar
CYCLES=$(echo "$STATUS_OUTPUT" | grep -i "Balance:" | head -1 | sed 's/[^0-9]//g')

if [ -n "$CYCLES" ] && [ "$CYCLES" -gt 0 ] 2>/dev/null; then
    # Convert to TC (trillion cycles)
    # Use awk for floating point math (bc might not be available)
    TC=$(awk "BEGIN {printf \"%.1f\", $CYCLES / 1000000000000}")
    echo "${TC}T"
else
    echo "unknown"
fi
