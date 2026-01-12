---
name: icp-deploy
description: Deploy to mainnet with safety checks
---

# ICP Deploy

Deploy to mainnet with safety checks. High-risk operation with guided workflow and verification steps.

## Usage

- `/icp-deploy --network ic` — Guided mainnet deployment
- `/icp-deploy --network ic --backend-only` — Deploy only backend
- `/icp-deploy --network ic --skip-checks` — Skip pre-deployment checks
- `/icp-deploy --network ic --yes` — Skip confirmation (for CI, dangerous)

## Prerequisites

- Must have `dfx.json` in project
- Must have correct dfx identity configured
- Must have cycles wallet with sufficient balance

## Execution Steps

### Step 1: Pre-flight Checks

```bash
# Check for dfx.json
[ -f "dfx.json" ] || { echo "Not an ICP project (no dfx.json found)"; exit 1; }

# Verify network flag
if [ "$NETWORK" != "ic" ]; then
    echo "Mainnet deployment requires --network ic flag"
    exit 1
fi
```

### Step 2: Identity and Wallet Verification

```bash
echo "Checking wallet configuration..."

# Get current identity
IDENTITY=$(dfx identity whoami)
PRINCIPAL=$(dfx identity get-principal)

echo "  ✓ Identity: $IDENTITY (principal: $PRINCIPAL)"

# Check cycles wallet
WALLET=$(dfx identity get-wallet --network ic 2>&1)
if [ $? -eq 0 ]; then
    WALLET_BALANCE=$(dfx wallet balance --network ic 2>&1 | grep -oE '[0-9.]+' | head -1)
    echo "  ✓ Cycles wallet: $WALLET (balance: ${WALLET_BALANCE}T)"
else
    echo "  ✗ No cycles wallet configured. Run: dfx identity set-wallet <wallet_id> --network ic"
    exit 1
fi
```

### Step 3: Check Canister Status (Upgrade vs Fresh Install)

Determine if this is an upgrade or fresh install for each canister:

```bash
echo "Checking canister status..."

# Check for existing mainnet canister_ids.json
if [ -f "canister_ids.json" ]; then
    for CANISTER in $(jq -r '.canisters | keys[]' dfx.json); do
        CANISTER_ID=$(jq -r ".[\"$CANISTER\"].ic // empty" canister_ids.json 2>/dev/null)
        if [ -n "$CANISTER_ID" ]; then
            echo "  ⚠ $CANISTER exists on mainnet — this is an UPGRADE"
        else
            echo "  ○ $CANISTER not on mainnet — this is a FRESH INSTALL"
        fi
    done
else
    echo "  ○ No mainnet canisters — all will be FRESH INSTALL"
fi
```

**Display:**
```
Checking canister status...
  ⚠ backend exists on mainnet — this is an UPGRADE
  ⚠ frontend exists on mainnet — this is an UPGRADE
  ○ new_canister not on mainnet — this is a FRESH INSTALL
```

### Step 4: Pre-deployment Checks (Unless --skip-checks)

Run code quality checks before deployment:

```bash
echo "Running pre-deployment checks..."

# Rust checks (if Cargo.toml exists)
if [ -f "Cargo.toml" ]; then
    echo "  Running cargo clippy..."
    if ! cargo clippy -- -D warnings 2>&1; then
        echo "  ✗ Clippy failed. Fix warnings or use --skip-checks"
        exit 1
    fi
    echo "  ✓ cargo clippy passed"

    echo "  Running cargo test..."
    if ! cargo test 2>&1; then
        echo "  ✗ Tests failed. Fix tests or use --skip-checks"
        exit 1
    fi
    echo "  ✓ cargo test passed"
fi

# Frontend build (if frontend canister exists)
FRONTEND=$(jq -r '.canisters | keys[] | select(endswith("_frontend"))' dfx.json | head -1)
if [ -n "$FRONTEND" ]; then
    FRONTEND_SOURCE=$(jq -r ".canisters[\"$FRONTEND\"].source[0] // empty" dfx.json)
    if [ -n "$FRONTEND_SOURCE" ]; then
        FRONTEND_DIR=$(dirname "$FRONTEND_SOURCE")
        if [ -f "$FRONTEND_DIR/package.json" ]; then
            echo "  Building frontend..."
            (cd "$FRONTEND_DIR" && npm run build) || {
                echo "  ✗ Frontend build failed"
                exit 1
            }
            echo "  ✓ Frontend builds successfully"
        fi
    fi
fi
```

### Step 5: Estimate Cycles Cost

Provide rough estimates based on WASM sizes:

```bash
echo "Estimating cycles cost..."

TOTAL_COST=0

for CANISTER in $(jq -r '.canisters | keys[]' dfx.json); do
    TYPE=$(jq -r ".canisters[\"$CANISTER\"].type" dfx.json)

    case "$TYPE" in
        rust|motoko|custom)
            # Backend canisters: ~0.2T per upgrade
            COST="0.2"
            ;;
        assets)
            # Asset canisters: ~0.5T (depends on asset size)
            COST="0.5"
            ;;
        pull)
            # Pull canisters: no cost (not deployed by us)
            COST="0"
            ;;
        *)
            COST="0.1"
            ;;
    esac

    if [ "$COST" != "0" ]; then
        echo "  $CANISTER: ~${COST}T"
        TOTAL_COST=$(awk "BEGIN {print $TOTAL_COST + $COST}")
    fi
done

echo "  Total estimated: ~${TOTAL_COST}T cycles"
echo "  Wallet balance after: ~$(awk "BEGIN {print $WALLET_BALANCE - $TOTAL_COST}")T"
```

### Step 6: Confirmation

Display full summary and request confirmation:

```
Ready to deploy to mainnet?

Identity: default (abc12-...)
Wallet: xyz98-... (12.4T)

Canisters:
  • backend: upgrade (preserves stable memory)
  • frontend: upgrade (syncs assets)

Estimated cost: ~0.7T cycles
Wallet after: ~11.7T

[Deploy all] [Deploy backend only] [Cancel]
```

Use AskUserQuestion:
**Question:** "Proceed with mainnet deployment?"
**Options:**
- "Deploy all"
- "Deploy backend only"
- "Cancel"

If `--yes` flag, skip confirmation (warn that this is dangerous).

### Step 7: Execute Deployment

```bash
echo "Deploying to mainnet..."

# Build deploy command
DEPLOY_CMD="dfx deploy --network ic"

if [ "$BACKEND_ONLY" = true ]; then
    BACKEND=$(jq -r '.canisters | keys[] | select(endswith("_backend"))' dfx.json | head -1)
    DEPLOY_CMD="dfx deploy $BACKEND --network ic"
fi

# Execute deployment
if ! $DEPLOY_CMD; then
    echo "✗ Deployment failed. Check output above."
    exit 1
fi
```

### Step 8: Log Deployment

Append to deployment log for audit trail:

```bash
# Create deployments.log if it doesn't exist
touch deployments.log

# Log each deployed canister
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")

for CANISTER in $(jq -r '.canisters | keys[]' dfx.json); do
    CANISTER_ID=$(jq -r ".[\"$CANISTER\"].ic // empty" canister_ids.json 2>/dev/null)
    if [ -n "$CANISTER_ID" ]; then
        echo "$TIMESTAMP mainnet upgrade $CANISTER $VERSION $CANISTER_ID" >> deployments.log
    fi
done
```

### Step 9: Display Results and Rollback Info

```
✓ Deployment complete!

Deployed canisters:
  • backend    abc12-defgh-...    https://abc12-defgh-....icp0.io
  • frontend   xyz98-klmno-...    https://xyz98-klmno-....icp0.io

Rollback commands (if needed):
  # Backend rollback (⚠ may lose data written after upgrade):
  dfx canister install backend --mode reinstall --wasm <previous_wasm> --network ic

Note: Stable memory changes are preserved across upgrades.
      Rollback only affects heap memory.

Deployment logged to: deployments.log
```

## Flags Reference

| Flag | Behavior |
|------|----------|
| `--network ic` | Required for mainnet deployment |
| `--backend-only` | Only deploy backend canister |
| `--skip-checks` | Skip cargo clippy/test/build |
| `--yes` | Skip confirmation (dangerous, for CI) |

## Safety Features

1. **Explicit network flag** — Must specify `--network ic`
2. **Upgrade detection** — Clearly shows UPGRADE vs FRESH INSTALL
3. **Pre-deployment checks** — Runs clippy, tests, frontend build
4. **Cycles estimation** — Shows expected cost
5. **Confirmation required** — Unless `--yes` (dangerous)
6. **Deployment logging** — Audit trail in deployments.log
7. **Rollback information** — Shows how to rollback if needed

## Error Handling

| Error | Message |
|-------|---------|
| No --network ic | "Mainnet deployment requires --network ic flag" |
| No cycles wallet | "No cycles wallet configured. Run: dfx identity set-wallet <wallet_id> --network ic" |
| Clippy fails | "Clippy failed. Fix warnings or use --skip-checks" |
| Tests fail | "Tests failed. Fix tests or use --skip-checks" |
| Deploy fails | Show dfx output, suggest checking cycles balance |

## Post-Deployment

After successful deployment:
- Run `/icp-status --network ic` to verify canister status
- Check cycles balances — deployment consumes cycles
- Test the deployed application
- Consider running `/icp-topup` if balances are low
