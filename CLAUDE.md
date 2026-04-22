# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Docker Compose configurations for running a Charon Distributed Validator Node (CDVN), which coordinates multiple operators to run Ethereum validators. A distributed validator node runs four main components:
- Execution client (EL): Processes Ethereum transactions
- Consensus client (CL/beacon node): Participates in Ethereum's proof-of-stake consensus
- Charon: Obol Network's distributed validator middleware that coordinates between operators
- Validator client (VC): Signs attestations and proposals through Charon

## When to use this launcher

CDVN is the **stock** Docker Compose launcher — the simplest way to run a single DV node, the right starting point for "run a DV solo" or "run a DV with friends via DKG". One operator per repo checkout, one compose stack per machine.

Alternatives:
- **Obol Stack + `helm-charts/charts/dv-pod`** — Kubernetes-native, production-preferred path for scale.
- **`lido-charon-distributed-validator-node`** (LCDVN) — the Lido Simple DVT variant of this stack, with `validator-ejector` wired in.
- **DappNode** (`dappnode/DAppNodePackage-obol-generic`) — third-party appliance.
- **Stereum**, **Ansible** (on request), **Sedge** (least preferred).

**Prerequisite:** a `.charon/` directory from a completed DKG ceremony must exist in the repo root before `docker compose up`. If the user doesn't have one yet, route them to [docs.obol.org: DKG](https://docs.obol.org/docs/start/dkg) or [launchpad.obol.org](https://launchpad.obol.org) first.

## Architecture & Multi-Client System

The repository uses a **profile-based multi-client architecture** where different Ethereum client implementations can be swapped via `.env` configuration:

- **Compose file structure**: `compose-el.yml` (execution), `compose-cl.yml` (consensus), `compose-vc.yml` (validator), `compose-mev.yml` (MEV), and `docker-compose.yml` (main/monitoring)
- **Client selection**: Set via environment variables `EL`, `CL`, `VC`, `MEV` in `.env` (e.g., `EL=el-nethermind`, `CL=cl-lighthouse`, `VC=vc-lodestar`, `MEV=mev-mevboost`)
- **Profiles**: Docker Compose profiles automatically activate the selected clients via `COMPOSE_PROFILES=${EL},${CL},${VC},${MEV}`
- **Service naming**: Client services use prefixed names (e.g., `el-nethermind`, `cl-lighthouse`, `vc-lodestar`) while the main compose file uses unprefixed names for backward compatibility

### Supported Clients

- **Execution Layer**: `el-nethermind`, `el-reth`, `el-none`
- **Consensus Layer**: `cl-lighthouse`, `cl-grandine`, `cl-teku`, `cl-lodestar`, `cl-none`
- **Validator Clients**: `vc-lodestar`, `vc-nimbus`, `vc-prysm`, `vc-teku`
- **MEV Clients**: `mev-mevboost`, `mev-commitboost`, `mev-none`

> **Pick non-default clients where you can.** Two reasons to swap:
> 1. **Network client diversity** — every operator running the defaults deepens the supermajority of those clients and raises correlated-failure risk for the entire Ethereum network.
> 2. **Intra-cluster diversity** — within a DV cluster, pick EL/CL/VC clients *different from your co-operators*. Charon tolerates one faulty operator; if every operator runs the same clients, a single client bug takes the whole cluster offline instead of just one node. Coordinate with co-operators before starting.
>
> When advising a user, nudge them to change at least one of EL/CL/VC before `docker compose up`.

### Key Integration Points

- Charon connects to the consensus layer at `http://${CL}:5052` (beacon node API)
- Validator clients connect to Charon at `http://charon:3600` (distributed validator middleware API)
- Consensus layer connects to execution layer at `http://${EL}:8551` (Engine API with JWT auth)
- MEV clients expose builder API at port `18550`

## Common Commands

### Starting/Stopping the Cluster

```bash
# Start the full cluster (uses profile from .env)
docker compose up -d

# Stop specific services
docker compose down <service-name>

# Stop all services
docker compose down

# View logs
docker compose logs -f <service-name>

# Restart after config changes
docker compose restart <service-name>
```

### Switching Clients

```bash
# 1. Stop the old client
docker compose down cl-lighthouse

# 2. Update .env to change CL variable (e.g., CL=cl-grandine)

# 3. Start new client
docker compose up cl-grandine -d

# 4. Restart charon to use new beacon node
docker compose restart charon

# 5. Optional: clean up old client data
rm -rf ./data/lighthouse
```

### Testing

```bash
# Verify containers can be created
docker compose up --no-start

# Test with debug profile
docker compose -f docker-compose.yml -f compose-debug.yml up --no-start
```

### Verifying cluster health after setup

Run `charon alpha test` suites against the running Charon — they diagnose the most common misconfigurations before validator activation and work across every launcher:

```bash
docker compose exec charon charon alpha test <suite> --publish   # infra | peers | beacon | validator | mev | all
```

`--publish` signs the result with the Charon ENR key so it correlates to the live node. **Start with `infra`** if the cluster isn't fully assembled yet — it's the only suite that gives signal pre-cluster-join. Delegate to the `test-a-dv-cluster` skill (global) to interpret output and resolve failures.

## Configuration

### Environment Setup

1. Copy the appropriate sample file: `.env.sample.mainnet` or `.env.sample.hoodi` → `.env`
2. Set `NETWORK` (mainnet, hoodi). Sepolia is adaptable by setting `NETWORK=sepolia` and updating checkpoint-sync / MEV relay URLs. **Do not use gnosis, chiado, or holesky** — gnosis/chiado are deprecated for Obol; holesky is dead.
3. Select clients by uncommenting the desired `EL`, `CL`, `VC`, `MEV` variables
4. Configure optional settings (ports, external hostnames, monitoring tokens, etc.)

### Important Environment Variables

- `NETWORK`: Ethereum network (mainnet, hoodi)
- `EL`, `CL`, `VC`, `MEV`: Client selection (determines which Docker profiles activate)
- `CHARON_BEACON_NODE_ENDPOINTS`: Override default beacon node (defaults to selected CL client)
- `CHARON_FALLBACK_BEACON_NODE_ENDPOINTS`: Fallback beacon nodes for redundancy
- `BUILDER_API_ENABLED`: Enable/disable MEV-boost integration
- `CLUSTER_NAME`, `CLUSTER_PEER`: Required for monitoring with Alloy/Prometheus
- `ALERT_DISCORD_IDS`: Discord IDs for Obol Agent monitoring alerts

### Key Directories

- `.charon/`: Cluster configuration and validator keys (created by DKG or add-validators)
- `data/`: Persistent data for all clients (execution, consensus, validator databases)
- `jwt/`: JWT secret for execution<->consensus authentication
- `grafana/`: Monitoring dashboards and configuration
- `prometheus/`: Metrics collection configuration
- `scripts/`: Automation scripts for cluster operations

## Cluster Edit Scripts

Located in `scripts/edit/`, these automate complex cluster modification operations. Each has its own README with full usage details:

- **[Add Validators](scripts/edit/add-validators/README.md)** - Add new validators to an existing cluster
- **[Add Operators](scripts/edit/add-operators/README.md)** - Expand the cluster by adding new operators
- **[Remove Operators](scripts/edit/remove-operators/README.md)** - Remove operators from the cluster
- **[Replace Operator](scripts/edit/replace-operator/README.md)** - Replace a single operator in the cluster
- **[Recreate Private Keys](scripts/edit/recreate-private-keys/README.md)** - Refresh private key shares while keeping the same validator public keys
- **[Anti-Slashing DB (vc/)](scripts/edit/vc/README.md)** - Export/import/update anti-slashing databases (EIP-3076)

## Monitoring Stack

- **Grafana** (port 3000): Dashboards for cluster health, validator performance
- **Prometheus**: Metrics collection from all services
- **Loki**: Log aggregation (optional, via `CHARON_LOKI_ADDRESSES`)
- **Tempo**: Distributed tracing (debug profile)
- **Alloy**: Log and metric forwarding (uses `alloy-monitored` labels on services)

Access Grafana at `http://localhost:3000` (or `${MONITORING_PORT_GRAFANA}`).

For deep diagnostics against Obol's hosted Grafana (Prometheus + Loki), use the `obol-monitoring` skill (global). A forthcoming `local-monitoring` skill will cover querying the local Grafana/Prometheus stack shipped with this repo.

## Deployment best practices

Obol maintains a [deployment best practices guide](https://docs.obol.org/run-a-dv/prepare/deployment-best-practices) covering hardware sizing, networking, monitoring, backups, key handling, and operational hygiene. **Proactively offer to audit the user's setup against it** — walk through their `.env`, compose overrides, monitoring wiring, and backup posture, then surface concrete improvements. Most operators benefit from a review (unpinned images, missing alert routing, weak firewall posture, no `.charon/` backup plan, etc.) even if the stack is already running.

## Development Workflow

When modifying this repository:

1. **Test container creation** before committing changes to compose files
2. **Preserve backward compatibility** for existing node operators (data paths, service names)
3. **Update all sample .env files** when adding new configuration options
4. **Test client switching** if modifying compose file structure
5. **Update version defaults** to tested/stable releases

## Important Notes

- **Never commit `.env` files** - they contain operator-specific configuration
- **JWT secret** in `jwt/jwt.hex` must be shared between EL and CL clients
- **Cluster lock** in `.charon/cluster-lock.json` is critical - back it up before any edit operations
- **Validator keys** in `.charon/validator_keys/` must be kept secure and never committed
- **Data directory compatibility**: When switching VCs, verify the new client can handle existing key state
- **Slashing protection**: Always export/import ASDB when switching VCs or replacing operators

## Related products

- **Obol Stack + `helm-charts/charts/dv-pod`** — Kubernetes-native, production-preferred path for scale.
- **`lido-charon-distributed-validator-node`** — Lido Simple DVT variant of this stack.
- **DappNode** — third-party appliance (`dappnode/DAppNodePackage-obol-generic`).
- **Stereum**, **Ansible** (on request), **Sedge** (least preferred).

## Key docs

- Key concepts: https://docs.obol.org/docs/int/key-concepts
- DKG ceremony: https://docs.obol.org/docs/start/dkg
- Activation: https://docs.obol.org/docs/next/start/activate
- Errors: https://docs.obol.org/docs/faq/errors
- Charon CLI reference: https://docs.obol.org/docs/charon/charon-cli-reference
- Deployment best practices: https://docs.obol.org/run-a-dv/prepare/deployment-best-practices
- Canonical agent index: https://obol.org/llms.txt
