# E2E Integration Tests for Edit Scripts

End-to-end tests that verify the cluster edit scripts work correctly across the full workflow.

## Prerequisites

- **Docker** running locally
- **jq** installed
- **Internet access** (charon ceremonies use the Obol P2P relay)

## Running

```bash
./scripts/edit/test/e2e_test.sh
```

Override the charon version:

```bash
CHARON_VERSION=v1.8.2 ./scripts/edit/test/e2e_test.sh
```

## What It Tests

| # | Test | Type | Description |
|---|------|------|-------------|
| 1 | add-validators | P2P ceremony (4 ops) | Adds 1 validator to a 4-operator, 1-validator cluster. Verifies 2 validators in output. |
| 2 | recreate-private-keys | P2P ceremony (4 ops) | Refreshes key shares. Verifies public_shares changed, same validator count. |
| 3 | add-operators | P2P ceremony (4+1 ops) | Adds 1 new operator. Verifies 5 operators in output. |
| 4 | remove-operators | P2P ceremony (4 of 5 ops) | Removes the added operator. Verifies 4 operators in output. |
| 5 | replace-operator | Offline (sequential) | Replaces operator 0. Verifies ENR changed in output. |
| 6 | update-anti-slashing-db | Standalone (no Docker) | Transforms EIP-3076 pubkeys between cluster-locks. |

## How It Works

1. Creates a real test cluster using `charon create cluster` (4 nodes, 1 validator)
2. Sets up 4 operator work directories with `.charon/` and `.env`
3. Interposes a **mock docker wrapper** (`test/bin/docker`) on `PATH`
   - Real `docker run` is used for charon ceremony commands (P2P relay)
   - `docker compose` commands are mocked (container lifecycle, ASDB export/import)
4. Runs each edit script through its happy path
5. Verifies outputs (validator count, operator count, key changes) at each step

## WORK_DIR Environment Variable

The test uses the `WORK_DIR` environment variable to redirect each script's working directory. When set, scripts use `WORK_DIR` as their repo root instead of computing it relative to the script location. This allows running multiple operator instances from isolated directories.

## Expected Runtime

Approximately 2-5 minutes depending on P2P relay connectivity. The P2P ceremonies (tests 1-4) require all operators to connect through the relay simultaneously.
