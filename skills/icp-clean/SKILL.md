---
name: icp-clean
description: Wipe local canister state and redeploy fresh
---

# ICP Clean

Wipe local canister state and redeploy fresh. Explicit operation, no surprises.

## Usage

- `/icp-clean` — Interactive confirmation, wipe all local state
- `/icp-clean --yes` — Skip confirmation
- `/icp-clean --keep-ii` — Preserve Internet Identity state (keep test logins)
- `/icp-clean --backend-only` — Only wipe backend canister state

## Execution Steps

### 1. Pre-flight Checks

```bash
[ -f "dfx.json" ] || { echo "Not an ICP project (no dfx.json found)"; exit 1; }
```

### 2. Check for Recent Clean

Look for recent clean to prevent accidental double-clean:

```bash
if [ -f ".dfx/last_clean" ]; then
    LAST_CLEAN=$(cat .dfx/last_clean)
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_CLEAN))

    if [ $DIFF -lt 300 ]; then  # 5 minutes
        MINUTES=$((DIFF / 60))
        echo "⚠ You cleaned $MINUTES minutes ago. Are you sure?"
    fi
fi
```

### 3. Show What Will Be Deleted

Display affected canisters with context:

```bash
echo "This will delete all local canister state and redeploy fresh."
echo ""
echo "Canisters to reset:"

# List canisters from dfx.json
for CANISTER in $(jq -r '.canisters | keys[]' dfx.json); do
    # Check if canister has data (exists in .dfx/local)
    if [ -d ".dfx/local/canisters/$CANISTER" ]; then
        case "$CANISTER" in
            *internet_identity*)
                echo "  • $CANISTER (will lose test user logins)"
                ;;
            *vetkd*|*chainkey*)
                echo "  • $CANISTER (will lose encryption keys)"
                ;;
            *backend*)
                echo "  • $CANISTER (has data)"
                ;;
            *)
                echo "  • $CANISTER"
                ;;
        esac
    else
        echo "  • $CANISTER (not deployed)"
    fi
done
```

**Special Warnings:**
```
⚠ VetKD/chainkey canister state will also be wiped — encrypted data unrecoverable
⚠ Internet Identity sessions will be lost — you'll need to re-authenticate
```

### 4. Confirmation (Unless --yes)

Use AskUserQuestion to confirm:

**Question:** "Proceed with clean? This will delete all local canister state."
**Options:**
- "Yes, clean everything"
- "No, cancel"

If `--yes` flag provided, skip confirmation.

### 5. Execute Clean

**Standard Clean (wipe everything):**
```bash
# Stop replica
dfx stop

# Remove all local state
rm -rf .dfx/local/

# Record clean time
mkdir -p .dfx
date +%s > .dfx/last_clean

# Restart replica
dfx start --background

# Wait for replica
TIMEOUT=30
while [ $TIMEOUT -gt 0 ]; do
    dfx ping &>/dev/null && break
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

# Deploy fresh
dfx deploy
```

**With --keep-ii (Preserve Internet Identity):**
```bash
# Don't stop replica — selectively delete canisters

# Get list of canisters to delete (exclude II)
CANISTERS=$(jq -r '.canisters | keys[] | select(contains("internet_identity") | not)' dfx.json)

for CANISTER in $CANISTERS; do
    echo "Stopping $CANISTER..."
    dfx canister stop "$CANISTER" 2>/dev/null || true

    echo "Deleting $CANISTER..."
    dfx canister delete "$CANISTER" 2>/dev/null || true
done

# Record clean time
mkdir -p .dfx
date +%s > .dfx/last_clean

# Redeploy (II will be skipped since it still exists)
dfx deploy
```

**With --backend-only:**
```bash
# Find backend canister
BACKEND=$(jq -r '.canisters | keys[] | select(endswith("_backend"))' dfx.json | head -1)

if [ -z "$BACKEND" ]; then
    echo "No backend canister found (looking for *_backend)"
    exit 1
fi

echo "Stopping $BACKEND..."
dfx canister stop "$BACKEND" 2>/dev/null || true

echo "Deleting $BACKEND..."
dfx canister delete "$BACKEND" 2>/dev/null || true

# Record clean time
mkdir -p .dfx
date +%s > .dfx/last_clean

# Redeploy just backend
dfx deploy "$BACKEND"
```

### 6. Post-Clean: Suggest Test Data

Look for test data scripts and suggest running them:

```bash
# Look for test data scripts
TEST_SCRIPTS=$(find scripts/ -name "*test*.sh" -o -name "*seed*.sh" -o -name "*create*.sh" 2>/dev/null || true)

if [ -n "$TEST_SCRIPTS" ]; then
    echo ""
    echo "Fresh environment ready. Create test data:"
    for SCRIPT in $TEST_SCRIPTS; do
        echo "  ./$SCRIPT"
    done
fi
```

### 7. Display Summary

```
✓ Clean complete

Canisters redeployed:
  • backend      rrkah-fqaaa-aaaaa-aaaaq-cai
  • frontend     ryjl3-tyaaa-aaaaa-aaaba-cai
  • internet_identity  rdmx6-jaaaa-aaaaa-aaadq-cai

Fresh environment ready. Create test data:
  ./scripts/create-test-profile.sh
```

## Flags Reference

| Flag | Behavior |
|------|----------|
| (none) | Interactive confirmation, wipe everything |
| `--yes` | Skip confirmation |
| `--keep-ii` | Preserve Internet Identity state |
| `--backend-only` | Only wipe backend canister state |

## Error Handling

| Error | Message |
|-------|---------|
| No dfx.json | "Not an ICP project (no dfx.json found)" |
| Replica won't stop | Show dfx output, suggest `killall dfx` |
| Deploy fails after clean | Show dfx error, state is clean but undeployed |

## Notes

- `--keep-ii` is a key pain point feature — preserves test user logins across cleans
- Clean is local-only — mainnet state is never affected
- VetKD state loss means encrypted data is unrecoverable; warn explicitly
