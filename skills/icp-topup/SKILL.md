---
name: icp-topup
description: Guided workflow for topping up canister cycles
---

# ICP Top-up

Guided workflow for topping up canister cycles on mainnet. Real money involved — includes verification steps.

## Usage

- `/icp-topup` — Interactive guided workflow
- `/icp-topup <canister> <amount>` — Direct top-up (still confirms)

## Prerequisites

- Must have mainnet canisters deployed (`canister_ids.json` exists)
- Must have cycles wallet or ICP balance
- Must be using correct dfx identity

## Execution Steps

### Step 1: Check Current Balances

```bash
echo "Step 1/4: Checking current balances..."
echo ""

# Check identity
IDENTITY=$(dfx identity whoami)
PRINCIPAL=$(dfx identity get-principal)
echo "Identity: $IDENTITY ($PRINCIPAL)"
echo ""

# Get all canisters from canister_ids.json
CANISTERS=$(jq -r '.[] | keys[]' canister_ids.json 2>/dev/null | sort -u)

if [ -z "$CANISTERS" ]; then
    echo "No mainnet canisters found. Deploy first with /icp-deploy"
    exit 1
fi
```

**Display Balance Table:**
```
┌─────────────────────────┬────────────────┬─────────────────┐
│ Canister                │ Current        │ Recommendation  │
├─────────────────────────┼────────────────┼─────────────────┤
│ backend                 │ 2.4T           │ ✓ ok            │
│ frontend                │ 1.1T           │ +0.9T → 2T      │
└─────────────────────────┴────────────────┴─────────────────┘
```

For each canister, get cycles:
```bash
dfx canister status <canister> --network ic 2>&1 | grep "Balance:" | awk '{print $2}'
```

**Recommendation Logic:**
- Current ≥ 2T: "✓ ok"
- Current 1-2T: "+XT → 2T" (suggest topping up to 2T)
- Current < 1T: "+XT → 2T (critical)"

### Step 2: Select Canister

Use AskUserQuestion:

**Question:** "Which canister to top up?"
**Options:**
- "<lowest_canister> (recommended)" — canister with lowest balance
- "<other_canister>" — other canisters
- "All below threshold" — top up all canisters below 2T
- "Custom"

If direct mode (`/icp-topup backend 1T`), skip to Step 4.

### Step 3: Select Amount

**Question:** "How many cycles to add to <canister>?"

Show current balance and calculate new balance for each option:

**Options:**
- "1T (recommended, brings to X.XT) — ~$1.30 USD"
- "2T (brings to X.XT) — ~$2.60 USD"
- "5T (brings to X.XT) — ~$6.50 USD"
- "Custom amount"

**Price Estimates (approximate):**
- 1T cycles ≈ $1.30 USD
- These are estimates; actual cost depends on ICP price

### Step 4: Select Funding Source

Check available funding sources:

```bash
# Check cycles wallet balance
WALLET_BALANCE=$(dfx wallet balance --network ic 2>&1 | grep -oE '[0-9.]+' | head -1)

# Check ICP ledger balance
ICP_BALANCE=$(dfx ledger balance --network ic 2>&1 | grep -oE '[0-9.]+' | head -1)
```

**Question:** "Top up from:"
**Options:**
- "Cycles wallet (balance: X.XT)"
- "Convert ICP (wallet balance: X.X ICP)"

### Step 5: Confirmation

Display full confirmation:

```
Confirm: Send <amount> cycles to <canister>?

Canister: <canister_id>
Amount: <cycles_raw> cycles (<amount>T)
From: <source>
Estimated new balance: <new_balance>T

[Confirm] [Cancel]
```

Use AskUserQuestion:
**Question:** "Confirm this top-up?"
**Options:**
- "Yes, send cycles"
- "No, cancel"

### Step 6: Execute Top-up

**From Cycles Wallet:**
```bash
dfx canister deposit-cycles <amount_raw> <canister> --network ic
```

**From ICP (convert):**
```bash
dfx ledger top-up <canister> --amount <icp_amount> --network ic
```

### Step 7: Verification

After execution, verify the new balance:

```bash
NEW_BALANCE=$(dfx canister status <canister> --network ic 2>&1 | grep "Balance:" | awk '{print $2}')
```

**Display Result:**
```
✓ Success!

<canister>
  Previous balance: 1.1T
  Added: 1.0T
  New balance: 2.1T
```

If balance didn't increase as expected, show warning:
```
⚠ Balance change smaller than expected. Transaction may still be processing.
   Run /icp-status --network ic to check current balance.
```

## Commands Reference

```bash
# Check cycles balance for a canister
dfx canister status <canister> --network ic

# Check cycles wallet balance
dfx wallet balance --network ic

# Check ICP balance
dfx ledger balance --network ic

# Top up from cycles wallet
dfx canister deposit-cycles <amount> <canister> --network ic

# Convert ICP to cycles and top up
dfx ledger top-up <canister> --amount <icp_amount> --network ic
```

## Cycles Conversion Reference

```
1 TC (trillion cycles) = 1,000,000,000,000 cycles
1 ICP ≈ 1.5 TC (varies with ICP price)
$1 USD ≈ 0.77 TC (approximate, late 2024)
```

## Error Handling

| Error | Message |
|-------|---------|
| No mainnet canisters | "No mainnet canisters found. Deploy first with /icp-deploy" |
| Insufficient cycles wallet | "Cycles wallet balance too low. Need X.XT, have Y.YT" |
| Insufficient ICP | "ICP balance too low for conversion" |
| Wrong identity | "Check identity: dfx identity whoami" |
| Network error | "Network error. Check connectivity and try again" |

## Safety Features

- Always shows confirmation before sending
- Displays estimated USD cost
- Verifies balance after transaction
- Shows canister ID (not just name) for verification
