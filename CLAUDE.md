# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Docker Compose configurations for running a Charon Distributed Validator Node (CDVN), which coordinates multiple operators to run Ethereum validators. A distributed validator node runs four main components:
- Execution client (EL): Processes Ethereum transactions
- Consensus client (CL/beacon node): Participates in Ethereum's proof-of-stake consensus
- Charon: Obol Network's distributed validator middleware that coordinates between operators
- Validator client (VC): Signs attestations and proposals through Charon

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

## Configuration

### Environment Setup

1. Copy the appropriate sample file: `.env.sample.mainnet` or `.env.sample.hoodi` → `.env`
2. Set `NETWORK` (mainnet, hoodi)
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

Located in `scripts/edit/`, these automate complex cluster modification operations:

### Replace Operator (`scripts/edit/replace-operator/`)

Automates the workflow when one operator in a distributed validator cluster needs to be replaced.

**For remaining operators:**
```bash
./scripts/edit/replace-operator/remaining-operator.sh \
    --new-enr "enr:-..." \
    --operator-index 2
```

**For new operators:**
```bash
# Step 1: Generate and share ENR
./scripts/edit/replace-operator/new-operator.sh --generate-enr

# Step 2: Apply received cluster-lock
./scripts/edit/replace-operator/new-operator.sh --cluster-lock ./received-cluster-lock.json
```

### Anti-Slashing Database Management (`scripts/edit/vc/`)

When switching validator clients or replacing operators, the anti-slashing database (ASDB) must be exported and imported to prevent slashing violations (EIP-3076 format).

```bash
# Export from current VC
./scripts/edit/vc/export_asdb.sh

# Import to new VC (after switching VC in .env)
./scripts/edit/vc/import_asdb.sh
```

Client-specific scripts are in subdirectories: `lodestar/`, `nimbus/`, `prysm/`, `teku/`.

### Recreate Private Keys (`scripts/edit/recreate-private-keys/`)

Recreates validator private keys from cluster-lock.json when they are lost but the cluster-lock file is still available.

```bash
./scripts/edit/recreate-private-keys/recreate-private-keys.sh
```

## Adding Validators

Starting with Charon v1.6, you can add validators to an existing cluster using `charon alpha add-validators`:

```bash
# Using Docker (recommended)
docker run --rm -v "$(pwd):/opt/charon" obolnetwork/charon:latest \
  alpha add-validators \
  --num-validators 10 \
  --withdrawal-addresses=0x<address> \
  --fee-recipient-addresses=0x<address> \
  --data-dir=/opt/charon/.charon \
  --output-dir=/opt/charon/output

# Apply the new configuration (backup first!)
docker compose stop charon <vc-service>
mv .charon .charon-backup
mv output .charon
docker compose up -d charon <vc-service>
```

**Note**: All operators must independently perform the upgrade. The cluster continues operating once threshold operators have upgraded.

## Monitoring Stack

- **Grafana** (port 3000): Dashboards for cluster health, validator performance
- **Prometheus**: Metrics collection from all services
- **Loki**: Log aggregation (optional, via `CHARON_LOKI_ADDRESSES`)
- **Tempo**: Distributed tracing (debug profile)
- **Alloy**: Log and metric forwarding (uses `alloy-monitored` labels on services)

Access Grafana at `http://localhost:3000` (or `${MONITORING_PORT_GRAFANA}`).

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
