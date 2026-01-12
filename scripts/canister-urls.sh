#!/bin/bash
# Generate URLs for canisters (local and mainnet)
# Input: canister_id, network
# Output: URL for accessing the canister

set -euo pipefail

CANISTER_ID=${1:-}
NETWORK=${2:-local}

if [ -z "$CANISTER_ID" ]; then
    echo "Usage: canister-urls.sh <canister_id> [network]"
    echo "  network: local (default) or ic"
    exit 1
fi

case "$NETWORK" in
    local)
        # Local replica URL (default port 4943)
        # Check for custom port in dfx.json or use default
        PORT=4943
        if [ -f "dfx.json" ]; then
            CUSTOM_PORT=$(jq -r '.networks.local.bind // empty' dfx.json 2>/dev/null | grep -oE '[0-9]+$' || echo "")
            if [ -n "$CUSTOM_PORT" ]; then
                PORT=$CUSTOM_PORT
            fi
        fi
        echo "http://127.0.0.1:${PORT}/?canisterId=${CANISTER_ID}"
        ;;
    ic|mainnet)
        # Mainnet uses icp0.io domain
        echo "https://${CANISTER_ID}.icp0.io"
        ;;
    *)
        echo "error: unknown network '$NETWORK' (use 'local' or 'ic')"
        exit 1
        ;;
esac
