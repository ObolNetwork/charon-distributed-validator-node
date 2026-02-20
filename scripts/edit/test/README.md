# E2E Integration Tests for Edit Scripts

End-to-end tests that verify the cluster edit scripts work correctly across the full workflow using real Docker Compose services.

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
CHARON_VERSION=v1.9.0-rc3 ./scripts/edit/test/e2e_test.sh
```

## What It Tests

| # | Test | Type | Description |
|---|------|------|-------------|
| 1 | recreate-private-keys | P2P ceremony (4 ops) | Refreshes key shares. Verifies public_shares changed, same validator count. |
| 2 | add-validators | P2P ceremony (4 ops) | Adds 1 validator to a 4-operator, 1-validator cluster. Verifies 2 validators in output. |
| 3 | add-operators | P2P ceremony (4+3 ops) | Adds 3 new operators (4→7). Verifies 7 operators in output. |
| 4 | remove-operators | P2P ceremony (6 of 7 ops) | Removes 1 operator (7→6). Verifies 6 operators in output. |

## How It Works

1. Creates a real test cluster using `charon create cluster` (4 nodes, 1 validator)
2. Sets up isolated operator directories, each with:
   - `.charon/` — cluster config and validator keys
   - `.env` — network and VC configuration
   - `docker-compose.e2e.yml` — minimal compose file (busybox for charon, real lodestar for VC)
   - `data/lodestar/` — persisted lodestar data directory
3. Starts Docker Compose stacks for each operator (isolated via `COMPOSE_PROJECT_NAME`)
4. Seeds lodestar anti-slashing databases from cluster-lock pubkeys
5. Runs each edit script through its happy path using `WORK_DIR`, `COMPOSE_FILE`, and `COMPOSE_PROJECT_NAME` for isolation
6. Verifies outputs (validator count, operator count, key changes) at each step
7. Restarts containers and re-seeds ASDB between tests (pubkeys change after ceremonies)

### Docker Compose Architecture

Each operator gets its own Docker Compose project (`e2e-op0`, `e2e-op1`, ...) running:
- **charon** — busybox placeholder (ceremonies use standalone `docker run`, not compose)
- **vc-lodestar** — real lodestar image so ASDB export/import works via `docker compose run`

Both services use `tail -f /dev/null` to stay alive without real network connections.

### Environment Variable Isolation

Edit scripts already preserve `COMPOSE_FILE` and `COMPOSE_PROJECT_NAME` from the environment around `.env` sourcing, so setting these externally works without script modifications:

```bash
WORK_DIR="$op_dir" \
COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
COMPOSE_PROJECT_NAME="e2e-op${i}" \
    "$REPO_ROOT/scripts/edit/recreate-private-keys/recreate-private-keys.sh"
```

## Expected Runtime

Approximately 5-10 minutes depending on P2P relay connectivity and Docker image pull times. The P2P ceremonies require all operators to connect through the relay simultaneously.
