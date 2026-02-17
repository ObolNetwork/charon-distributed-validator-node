# Remove-Operators Scripts

Scripts to automate the [remove-operators ceremony](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/remove-operators) for Charon distributed validators.

## Overview

These scripts help operators remove specific operators from an existing distributed validator cluster while preserving all validators. This is useful for:

- **Operator offboarding**: Removing an operator who is leaving the cluster
- **Cluster downsizing**: Reducing the number of operators
- **Security response**: Removing a compromised operator

**Important**: This is a coordinated ceremony. All participating operators must run their respective scripts simultaneously to complete the process.

> **Warning**: This is an alpha feature in Charon and is not yet recommended for production use.

There are two scripts for the two roles involved:

- **`remaining-operator.sh`** - For operators staying in the cluster
- **`removed-operator.sh`** - For operators being removed who need to participate (only required when removal exceeds fault tolerance)

### Fault Tolerance

The cluster's fault tolerance is `f = operators - threshold`. When removing more operators than `f`, removed operators must participate in the ceremony by running `removed-operator.sh` with the `--participating-operator-enrs` flag.

When the removal is within fault tolerance, removed operators simply stop their nodes after the ceremony completes.

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- `.charon` directory with `cluster-lock.json` and `validator_keys`
- Docker running
- `jq` installed

## For Remaining Operators

Automates the complete workflow for operators staying in the cluster:

```bash
./scripts/edit/remove-operators/remaining-operator.sh \
    --operator-enrs-to-remove "enr:-..."
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--operator-enrs-to-remove <enrs>` | Yes | Comma-separated ENRs of operators to remove |
| `--participating-operator-enrs <enrs>` | When exceeding fault tolerance | Comma-separated ENRs of all participating operators |
| `--new-threshold <N>` | No | Override default threshold (defaults to ceil(n * 2/3)) |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

### Workflow

1. **Export ASDB** - Export anti-slashing database from running VC
2. **Run ceremony** - P2P coordinated remove-operators ceremony with all participants
3. **Update ASDB** - Replace pubkeys in exported ASDB to match new cluster-lock
4. **Stop containers** - Stop charon and VC
5. **Backup and replace** - Backup current `.charon/` to `./backups/`, install new configuration
6. **Import ASDB** - Import updated anti-slashing database
7. **Restart containers** - Start charon and VC with new configuration

## For Removed Operators

Only required when the removal exceeds the cluster's fault tolerance. In that case, removed operators must participate in the ceremony to provide their key shares.

```bash
./scripts/edit/remove-operators/removed-operator.sh \
    --operator-enrs-to-remove "enr:-..." \
    --participating-operator-enrs "enr:-...,enr:-...,enr:-..."
```

If the removal is within fault tolerance, removed operators do **not** need to run this script - simply stop your node after the remaining operators complete the ceremony.

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--operator-enrs-to-remove <enrs>` | Yes | Comma-separated ENRs of operators to remove |
| `--participating-operator-enrs <enrs>` | Yes | Comma-separated ENRs of ALL participating operators |
| `--new-threshold <N>` | No | Override default threshold (defaults to ceil(n * 2/3)) |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

## Current Limitations

- The new cluster configuration will not be reflected on the Obol Launchpad
- The cluster will have a new cluster hash (different observability identifier)
- All remaining operators must have valid validator keys to participate
- The old cluster must be completely stopped before the new cluster can operate

## Related

- [Add-Validators Workflow](../add-validators/README.md)
- [Add-Operators Workflow](../add-operators/README.md)
- [Recreate-Private-Keys Workflow](../recreate-private-keys/README.md)
- [Replace-Operator Workflow](../replace-operator/README.md)
- [Anti-Slashing DB Scripts](../vc/README.md)
- [Obol Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/remove-operators)
