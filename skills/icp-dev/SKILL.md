---
name: icp-dev
description: Bootstrap local development environment (start replica, deploy)
---

# ICP Dev Bootstrap

"Start my day" command. One command to get local development environment ready.

## Usage

- `/icp-dev` — Start replica (if needed) and deploy, preserving state
- `/icp-dev --clean` — Wipe state and redeploy fresh (delegates to /icp-clean)
- `/icp-dev --backend-only` — Only deploy backend canister
- `/icp-dev --skip-frontend` — Deploy all except frontend (faster iteration)

## Execution Steps

### 1. Pre-flight Checks

**Detect ICP project:**
```bash
[ -f "dfx.json" ] || { echo "Not an ICP project (no dfx.json found)"; exit 1; }
```

**Check dfx installation:**
```bash
command -v dfx &>/dev/null || { echo "dfx not installed. Install: sh -ci \"$(curl -fsSL https://internetcomputer.org/install.sh)\""; exit 1; }
```

### 2. Check for VetKD Requirements

Detect if project uses VetKD and fetch artifacts if needed:

```bash
# Check if dfx.json references vetkeys/chainkey files
if jq -e '.canisters | to_entries[] | select(.value.wasm | contains("vetkeys") or contains("chainkey"))' dfx.json >/dev/null 2>&1; then
    # Check if artifacts exist
    if [ ! -f "vetkeys/chainkey_testing_canister.wasm" ] || [ ! -f "vetkeys/chainkey_testing_canister.did" ]; then
        echo "VetKD canister detected, fetching artifacts..."
        # Run fetch script from plugin
        ~/.claude/plugins/icp-dev/scripts/fetch-vetkeys.sh
    fi
fi
```

### 3. Check Replica Status

```bash
if dfx ping &>/dev/null; then
    echo "✓ Replica already running"

    # Check uptime for staleness warning
    UPTIME_JSON=$(~/.claude/plugins/icp-dev/scripts/replica-status.sh)
    UPTIME_SECONDS=$(echo "$UPTIME_JSON" | jq -r '.uptime_seconds // 0')

    # Warn if running > 24 hours (86400 seconds)
    if [ "$UPTIME_SECONDS" -gt 86400 ]; then
        echo "⚠ Replica running for >24h — consider restarting with: dfx stop && dfx start --background"
    fi
else
    echo "Starting replica..."
    dfx start --background

    # Wait for replica to be ready (max 30s)
    TIMEOUT=30
    while [ $TIMEOUT -gt 0 ]; do
        if dfx ping &>/dev/null; then
            echo "✓ Replica ready"
            break
        fi
        sleep 1
        TIMEOUT=$((TIMEOUT - 1))
    done

    if [ $TIMEOUT -eq 0 ]; then
        echo "✗ Timeout waiting for replica. Check: dfx start --background"
        exit 1
    fi
fi
```

### 4. Handle --clean Flag

If `--clean` flag is present, delegate to `/icp-clean` skill:
```
Invoke /icp-clean skill, then return here for deployment
```

### 5. Check Existing State

```bash
if [ -d ".dfx/local" ]; then
    # Get last deploy time from canister_ids.json modification time
    if [ -f ".dfx/local/canister_ids.json" ]; then
        LAST_DEPLOY=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" .dfx/local/canister_ids.json 2>/dev/null || stat -c "%y" .dfx/local/canister_ids.json 2>/dev/null | cut -d. -f1)
        echo "Preserving existing state (last deployed: $LAST_DEPLOY)"
    fi
else
    echo "Fresh environment — first deployment"
fi
```

### 6. Deploy Canisters

Build deploy command based on flags:

```bash
DEPLOY_CMD="dfx deploy"

# Handle canister filters
if [ "$BACKEND_ONLY" = true ]; then
    # Find backend canister (usually named *_backend)
    BACKEND=$(jq -r '.canisters | keys[] | select(endswith("_backend"))' dfx.json | head -1)
    DEPLOY_CMD="dfx deploy $BACKEND"
elif [ "$SKIP_FRONTEND" = true ]; then
    # Deploy each non-frontend canister
    CANISTERS=$(jq -r '.canisters | keys[] | select(endswith("_frontend") | not)' dfx.json)
    for c in $CANISTERS; do
        dfx deploy "$c"
    done
    # Skip the main deploy command
    DEPLOY_CMD=""
fi

# Run deployment
if [ -n "$DEPLOY_CMD" ]; then
    $DEPLOY_CMD
fi
```

### 7. Collect Results and Display Summary

After deployment, gather canister info and display:

```bash
# Get canister IDs
CANISTER_IDS=$(cat .dfx/local/canister_ids.json 2>/dev/null || echo "{}")

# Get replica PID
PID=$(pgrep -f "replica" | head -1 || echo "unknown")
```

**Output Format:**
```
✓ Replica running (pid <PID>)
✓ Deployed <N> canisters

  Canister               ID                             URL
  ─────────────────────────────────────────────────────────────────────────────
  backend                rrkah-fqaaa-aaaaa-aaaaq-cai    http://127.0.0.1:4943/?canisterId=...
  frontend               ryjl3-tyaaa-aaaaa-aaaba-cai    http://127.0.0.1:4943/?canisterId=...
  internet_identity      rdmx6-jaaaa-aaaaa-aaadq-cai    http://127.0.0.1:4943/?canisterId=...

Frontend: http://127.0.0.1:4943/?canisterId=<frontend_id>
```

Use `scripts/canister-urls.sh` to generate URLs.

## Error Handling

| Error | Message |
|-------|---------|
| dfx not installed | "dfx not installed. Install: sh -ci \"$(curl -fsSL https://internetcomputer.org/install.sh)\"" |
| No dfx.json | "Not an ICP project (no dfx.json found)" |
| Replica start fails | Show dfx output, suggest checking port 4943 |
| Deploy fails | Show dfx error, note partial state may exist |
| Timeout waiting | "Timeout waiting for replica. Check system resources." |

## Flags Reference

| Flag | Behavior |
|------|----------|
| (none) | Preserve state, deploy all canisters |
| `--clean` | Wipe state first (delegates to /icp-clean) |
| `--backend-only` | Only deploy backend canister |
| `--skip-frontend` | Deploy all except frontend (faster) |

## Post-Deploy Tips

After successful deployment, remind user:
- Frontend URL is clickable
- Use `/icp-status` to check canister status anytime
- Use `/icp-clean` if you need fresh state
