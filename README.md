# ICP Claude Code Plugin

A Claude Code plugin that makes Internet Computer (ICP) development feel native and seamless. The plugin provides slash commands for common workflows (local dev, deployment, cycles management) with safety guardrails for risky operations.

**Design philosophy:** Hybrid approach - quick slash commands for routine tasks, guided skills with verification steps for operations with real consequences (mainnet deployment, cycles spending).

---

## Pain Points Addressed

### Local Development Cycle
1. **Startup friction** - Remembering to start replica, waiting for it, checking if already running, dealing with stale state
2. **State management** - Deciding when to wipe vs preserve canister state, accidentally losing test data, recreating test scenarios, losing Internet Identity sessions on clean

### Cycles Management
1. **Visibility** - Not knowing current balances until explicitly checking, surprised by low cycles
2. **Top-up workflow** - Remembering the right commands, cycles wallet vs direct top-up, ICP to cycles conversion

### Secondary (Phase 3)
3. **Mainnet deployment** - Safety checks, upgrade vs fresh install awareness, cycles cost estimation
4. **Multi-environment** - Switching between local/mainnet, tracking canister IDs

---

## Plugin Structure

```
icp-dev/
├── skills/
│   ├── icp-dev.md           # Bootstrap command (start replica, deploy, show status)
│   ├── icp-status.md        # Comprehensive status dashboard
│   ├── icp-topup.md         # Guided cycles top-up workflow
│   ├── icp-deploy.md        # Mainnet deployment with safety checks
│   └── icp-clean.md         # Wipe state and redeploy fresh
├── agents/
│   └── icp-explorer.md      # Agent for ICP-specific codebase questions (future)
├── scripts/
│   ├── replica-status.sh    # Check if replica is running
│   ├── cycles-check.sh      # Get cycles for all canisters in dfx.json
│   ├── canister-urls.sh     # Generate URLs for local/mainnet
│   └── fetch-vetkeys.sh     # Download VetKD testing canister from DFINITY GitHub
├── templates/
│   └── dfx-outputs.md       # Common dfx output patterns for parsing
└── plugin.json              # Plugin metadata, slash command registration
```

### Design Decisions

- **Skills for slash commands** - Each `/icp-*` command maps to a skill markdown file
- **Scripts for reusable logic** - Shell scripts handle dfx interactions, skills orchestrate them
- **Separation of quick vs guided** - `/icp-status` is instant info, `/icp-topup` is guided with verification

---

### `/icp-dev` - Bootstrap Command

**Purpose:** "Start my day" command. One command to get development environment ready.

**Trigger:** `/icp-dev`, `/icp-dev --clean`, `/icp-dev --backend-only`

**Implementation file:** `skills/icp-dev.md`

#### Behavior

1. **Pre-flight checks (instant)**
   - Detect `dfx.json` in project
   - Check if replica is already running (`dfx ping`)
   - Check for existing canister IDs in `.dfx/local/canister_ids.json`

2. **Replica management**
   - If not running → start with `dfx start --background`
   - If running but stale (started >24h ago) → warn and offer restart
   - Wait for replica ready (poll `dfx ping` with timeout, max 30s)

3. **Deployment with state control**
   - Default behavior: preserve state (`dfx deploy`)
   - With `--clean`: wipe and redeploy (delegate to `/icp-clean`)
   - With `--backend-only`: `dfx deploy myapp_backend`

4. **Output summary**
   ```
   ✓ Replica running (pid 12345)
   ✓ Deployed 3 canisters

     backend              rrkah-fqaaa-aaaaa-aaaaq-cai   http://127.0.0.1:4943/?canisterId=...
     frontend             ryjl3-tyaaa-aaaaa-aaaba-cai   http://127.0.0.1:4943/?canisterId=...
     internet_identity    rdmx6-jaaaa-aaaaa-aaadq-cai   http://127.0.0.1:4943/?canisterId=...

   ⚠ Cycles check skipped (local network)

   Frontend: http://127.0.0.1:4943/?canisterId=ryjl3-tyaaa-aaaaa-aaaba-cai
   ```

#### State Management UX

- **First run detection:** Check for `.dfx/local/` directory
  - If doesn't exist →  fresh deploy, no prompt
  - If exists →  show "Preserving existing state (last deployed X ago)"
- **Explicit clean:** Always require `--clean` flag to wipe, never prompt

#### Flags

| Flag | Behavior |
|------|----------|
| (none) | Preserve state, deploy all canisters |
| `--clean` | Wipe state first (delegates to /icp-clean) |
| `--backend-only` | Only deploy backend canister |
| `--skip-frontend` | Deploy all except frontend (faster) |


### `/icp-clean` - State Management

**Purpose:** Wipe local canister state and redeploy fresh. Explicit, no surprises.

**Trigger:** `/icp-clean`, `/icp-clean --yes`, `/icp-clean --keep-ii`

**Implementation file:** `skills/icp-clean.md`

#### Flags

| Flag | Behavior |
|------|----------|
| (none) | Interactive confirmation, wipe everything |
| `--yes` | Skip confirmation |
| `--keep-ii` | Preserve Internet Identity state (key feature!) |
| `--backend-only` | Only wipe backend canister state |

---

### `/icp-topup` - Cycles Top-up Workflow

**Purpose:** Guided workflow for topping up canister cycles. Real money involved, so verification steps are important.

**Trigger:** `/icp-topup`, `/icp-topup <canister> <amount>`

**Implementation file:** `skills/icp-topup.md`


### 5. `/icp-deploy` - Mainnet Deployment

**Purpose:** Deploy to mainnet with safety checks. High-risk operation, so guided workflow with verification.

**Trigger:** `/icp-deploy --network ic`

**Implementation file:** `skills/icp-deploy.md`

Options:
- `Deploy all`
- `Deploy backend only`
- `Cancel`

#### Safety Features

1. **Upgrade vs Install detection**
   - Check `canister_ids.json` for mainnet entries
   - Clearly indicate UPGRADE vs FRESH INSTALL

2. **Pre-deployment checks** (configurable, skippable)
   ```bash
   cargo clippy -- -D warnings
   cargo test
   cd src/myapp_frontend && npm run build
   ```

3. **Cycles cost estimation**
   - Backend Wasm size →  estimate install cycles
   - Frontend asset size →  estimate asset upload cycles

4. **Explicit confirmation**
   - Always require confirmation for mainnet
   - Show exactly what will happen

5. **Deployment log**
   - Append to `deployments.log`:
     ```
     2026-01-10T15:30:00Z mainnet upgrade backend v1.2.3 abc12...
     2026-01-10T15:30:45Z mainnet upgrade frontend v1.2.3 xyz98...
     ```

#### Flags

| Flag | Behavior |
|------|----------|
| `--network ic` | Required for mainnet |
| `--skip-checks` | Skip cargo clippy/test |
| `--backend-only` | Only deploy backend |
| `--yes` | Skip confirmation (dangerous, for CI) |

#### Rollback Information

After deployment, show rollback info:
```
✓ Deployment complete!

Rollback commands (if needed):
  dfx canister install myapp_backend --mode reinstall --wasm .dfx/ic/canisters/backend/backend_previous.wasm --network ic

Note: Rollback may lose data written after upgrade. Stable memory changes are preserved.
```

---

## Configuration System (Future)

For shareability, support project-level configuration:

**`.claude/icp-config.json` in project root:**
```json
{
  "version": "1",
  "cycles": {
    "warningThreshold": "1.5T",
    "criticalThreshold": "1T",
    "targetBalance": "3T"
  },
  "deploy": {
    "preChecks": ["cargo clippy -- -D warnings", "cargo test"],
    "skipCanisters": ["internet_identity"]
  },
  "clean": {
    "testDataScript": "./scripts/create-test-profile.sh",
    "preserveOnClean": ["internet_identity"]
  },
  "status": {
    "hideFromStatus": []
  }
}
```

**Default values** (when no config):
- Warning threshold: 1.5T
- Critical threshold: 1T
- Pre-checks: clippy + test
- No skip canisters

---

## VetKD Artifact Management

Projects using VetKD encryption require the `chainkey-testing-canister` for local development. Rather than committing binary artifacts to the plugin or project repository, the plugin should fetch them on demand.

### Artifact Sources

| Artifact | URL | Version |
|----------|-----|---------|
| WASM (compressed) | `https://github.com/dfinity/chainkey-testing-canister/releases/download/v0.2.0/chainkey_testing_canister.wasm.gz` | v0.2.0 |
| Candid interface | `https://raw.githubusercontent.com/dfinity/chainkey-testing-canister/v0.2.0/chainkey_testing_canister.did` | v0.2.0 |

### Integration with `/icp-dev`

The `/icp-dev` command should automatically handle VetKD artifact setup:

1. **Detection:** Check if `dfx.json` references `vetkd_system_api` or similar VetKD canister
2. **Check local files:** Look for existing `vetkeys/` directory with required files
3. **Fetch if missing:** Download artifacts from DFINITY GitHub releases
4. **Version pinning:** Use a known stable version (currently v0.2.0)


### Version Management

For future flexibility, version can be:
1. **Default:** Hardcoded in plugin (v0.2.0)
2. **Project override:** Read from `.claude/icp-config.json`:
   ```json
   {
     "vetkeys": {
       "version": "v0.2.0"
     }
   }
   ```
3. **Environment override:** `VETKEYS_VERSION=v0.3.0 /icp-dev`

---

