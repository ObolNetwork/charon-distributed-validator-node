# Add-Operators Scripts

Scripts to automate the [add-operators ceremony](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-operators) for Charon distributed validators.

## Overview

These scripts help operators expand an existing distributed validator cluster by adding new operators. This is useful for:

- **Cluster expansion**: Adding more operators for increased redundancy
- **Decentralization**: Distributing validator duties across more parties
- **Resilience**: Expanding the operator set while maintaining the same validators

**Important**: This is a coordinated ceremony. All operators (existing AND new) must run their respective scripts simultaneously to complete the process.

> **Warning**: This is an alpha feature in Charon and is not yet recommended for production use.

There are two scripts for the two roles involved:

- **`existing-operator.sh`** - For operators already in the cluster
- **`new-operator.sh`** - For new operators joining the cluster

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- Docker running
- `jq` installed
- **Existing operators**: `.charon` directory with `cluster-lock.json` and `validator_keys`
- **New operators**: Charon ENR private key (generated via `--generate-enr`)

## For Existing Operators

Automates the complete workflow for operators already in the cluster:

```bash
./scripts/edit/add-operators/existing-operator.sh \
    --new-operator-enrs "enr:-..."
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--new-operator-enrs <enrs>` | Yes | Comma-separated ENRs of new operators |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

### Workflow

1. **Export ASDB** - Stop VC if running and export anti-slashing database
2. **Run ceremony** - P2P coordinated add-operators ceremony with all operators
3. **Update ASDB** - Replace pubkeys in exported ASDB to match new cluster-lock
4. **Stop containers** - Stop charon and VC
5. **Backup and replace** - Backup current `.charon/` to `./backups/`, install new configuration
6. **Import ASDB** - Import updated anti-slashing database
7. **Print start commands** - Display commands to start containers manually (wait ~2 epochs before starting)

## For New Operators

Two-step workflow for new operators joining the cluster.

**Step 1:** Generate ENR and share with existing operators:

```bash
./scripts/edit/add-operators/new-operator.sh --generate-enr
```

**Step 2:** Download the existing cluster-lock from one of the existing operators:

```bash
curl -o .charon/cluster-lock.json https://example.com/cluster-lock.json
```

**Step 3:** Run the ceremony with the cluster-lock:

```bash
./scripts/edit/add-operators/new-operator.sh \
    --new-operator-enrs "enr:-...,enr:-..." \
    --cluster-lock .charon/cluster-lock.json
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--new-operator-enrs <enrs>` | For ceremony | Comma-separated ENRs of ALL new operators |
| `--cluster-lock <path>` | For ceremony | Path to existing cluster-lock.json |
| `--generate-enr` | No | Generate new ENR private key |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

## Related

- [Add-Validators Workflow](../add-validators/README.md)
- [Remove-Operators Workflow](../remove-operators/README.md)
- [Recreate-Private-Keys Workflow](../recreate-private-keys/README.md)
- [Replace-Operator Workflow](../replace-operator/README.md)
- [Anti-Slashing DB Scripts](../vc/README.md)
- [Obol Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-operators)
