#!/bin/bash
# Fetch VetKD testing canister artifacts from DFINITY GitHub
# Version pinned for reproducibility

set -euo pipefail

VETKEYS_VERSION="${VETKEYS_VERSION:-v0.2.0}"
VETKEYS_DIR="${VETKEYS_DIR:-vetkeys}"

WASM_URL="https://github.com/dfinity/chainkey-testing-canister/releases/download/${VETKEYS_VERSION}/chainkey_testing_canister.wasm.gz"
DID_URL="https://raw.githubusercontent.com/dfinity/chainkey-testing-canister/${VETKEYS_VERSION}/chainkey_testing_canister.did"

# Check if already present
if [ -f "${VETKEYS_DIR}/chainkey_testing_canister.wasm" ] && [ -f "${VETKEYS_DIR}/chainkey_testing_canister.did" ]; then
    echo "VetKD artifacts already present in ${VETKEYS_DIR}/"
    exit 0
fi

# Check for curl
if ! command -v curl &>/dev/null; then
    echo "error: curl is required but not installed"
    exit 1
fi

echo "Fetching VetKD testing canister (${VETKEYS_VERSION})..."
mkdir -p "${VETKEYS_DIR}"

# Fetch WASM (compressed)
echo "  Downloading chainkey_testing_canister.wasm..."
if ! curl -fsSL "${WASM_URL}" -o "${VETKEYS_DIR}/chainkey_testing_canister.wasm.gz"; then
    echo "error: Failed to download WASM from ${WASM_URL}"
    exit 1
fi

# Decompress WASM
if ! gunzip -f "${VETKEYS_DIR}/chainkey_testing_canister.wasm.gz"; then
    echo "error: Failed to decompress WASM file"
    exit 1
fi

# Fetch Candid interface
echo "  Downloading chainkey_testing_canister.did..."
if ! curl -fsSL "${DID_URL}" -o "${VETKEYS_DIR}/chainkey_testing_canister.did"; then
    echo "error: Failed to download Candid interface from ${DID_URL}"
    # Clean up partial download
    rm -f "${VETKEYS_DIR}/chainkey_testing_canister.wasm"
    exit 1
fi

echo "✓ VetKD artifacts ready in ${VETKEYS_DIR}/"
echo "  - chainkey_testing_canister.wasm"
echo "  - chainkey_testing_canister.did"
