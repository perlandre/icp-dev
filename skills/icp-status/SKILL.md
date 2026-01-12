---
name: icp-status
description: Show ICP project status dashboard (replica, canisters, cycles)
---

# ICP Status Dashboard

Quick, read-only view of ICP project state. No side effects.

## Usage

- `/icp-status` — Show local network status
- `/icp-status --network ic` — Show mainnet status

## Execution Steps

### 1. Detect ICP Project

Check for `dfx.json` in current directory or parents:

```bash
# Find dfx.json
if [ ! -f "dfx.json" ]; then
    # Check parent directories
    SEARCH_DIR=$(pwd)
    while [ "$SEARCH_DIR" != "/" ]; do
        if [ -f "$SEARCH_DIR/dfx.json" ]; then
            cd "$SEARCH_DIR"
            break
        fi
        SEARCH_DIR=$(dirname "$SEARCH_DIR")
    done
fi

[ -f "dfx.json" ] || { echo "Not an ICP project (no dfx.json found)"; exit 1; }
```

If not found, report: "Not an ICP project (no dfx.json found)"

### 2. Determine Network

Parse the `--network` flag:
- Default: `local`
- `--network ic` or `--network mainnet`: mainnet

### 3. Check Replica Status (Local Only)

For local network, check if replica is running:

```bash
dfx ping 2>/dev/null && echo "running" || echo "stopped"
```

If running, get additional info:
- PID: `pgrep -f "replica" | head -1`
- Calculate uptime from process start time

### 4. Get Project Name

Extract from `dfx.json` or use directory name:

```bash
PROJECT_NAME=$(jq -r '.dfx // empty' dfx.json 2>/dev/null || basename "$(pwd)")
```

### 5. Get Canister List

```bash
jq -r '.canisters | keys[]' dfx.json
```

### 6. Get Status for Each Canister

For each canister, run:

```bash
dfx canister status <canister_name> --network <network> 2>&1
```

Extract:
- Canister ID (from `.dfx/local/canister_ids.json` or `canister_ids.json`)
- Status: Running, Stopped, or "Not deployed"
- Cycles: Only for mainnet (local shows "(local)")

### 7. Format Output

**Local Network Format:**
```
ICP Project: <project_name>
Network: local (replica running, pid <PID>, uptime <TIME>)

┌─────────────────────────┬──────────────────────────────┬─────────────────┬────────────┐
│ Canister                │ ID                           │ Status          │ Cycles     │
├─────────────────────────┼──────────────────────────────┼─────────────────┼────────────┤
│ backend                 │ rrkah-fqaaa-aaaaa-aaaaq-cai  │ Running         │ (local)    │
│ frontend                │ ryjl3-tyaaa-aaaaa-aaaba-cai  │ Running         │ (local)    │
└─────────────────────────┴──────────────────────────────┴─────────────────┴────────────┘

dfx version: <version>
```

**Mainnet Format with Cycles:**
```
ICP Project: <project_name>
Network: ic (mainnet)

┌─────────────────────────┬──────────────────────────────┬─────────────────┬────────────────┐
│ Canister                │ ID                           │ Status          │ Cycles         │
├─────────────────────────┼──────────────────────────────┼─────────────────┼────────────────┤
│ backend                 │ abc12-defgh-...              │ Running         │ 2.4T (▲ ok)    │
│ frontend                │ xyz98-klmno-...              │ Running         │ 1.1T (⚠ low)   │
└─────────────────────────┴──────────────────────────────┴─────────────────┴────────────────┘

⚠ frontend cycles below 1.5T threshold — consider running /icp-topup
```

### 8. Cycles Thresholds

| Status | Symbol | Range |
|--------|--------|-------|
| OK | `▲ ok` | > 2T cycles |
| Low | `⚠ low` | 1T - 2T cycles |
| Critical | `🔴 critical` | < 1T cycles |

Show warning message for any canister below 1.5T threshold.

## Edge Cases

- **Replica not running (local):** Show "Replica: stopped" and skip canister status checks
- **Canister not deployed:** Show "Not deployed" in status column
- **Network unreachable:** Error with suggestion to check network connectivity
- **No canister_ids.json for mainnet:** Show "Not deployed to mainnet"

## Helper Scripts

Use plugin scripts for reusable logic:
- `scripts/replica-status.sh` — JSON output of replica status
- `scripts/cycles-check.sh` — Get cycles for a canister

## Example Commands

```bash
# Get dfx version
dfx --version

# Check canister IDs file
cat .dfx/local/canister_ids.json 2>/dev/null || echo "{}"

# Get canister status
dfx canister status <name> --network local
```
