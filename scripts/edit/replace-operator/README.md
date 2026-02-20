# Replace-Operator Scripts

Scripts to automate the [replace-operator workflow](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/replace-operator) for Charon distributed validators.

## Overview

These scripts help operators replace a single operator in an existing distributed validator cluster. This is useful for:

- **Operator rotation**: Replacing an operator who is leaving the cluster
- **Infrastructure migration**: Moving an operator to new infrastructure
- **Recovery**: Replacing an operator whose keys may have been compromised

> **Warning**: This is an alpha feature in Charon and is not yet recommended for production use.

There are two scripts for the two roles involved:

- **`remaining-operator.sh`** - For operators staying in the cluster (runs the ceremony)
- **`new-operator.sh`** - For the new operator joining the cluster

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- `.charon` directory with `cluster-lock.json` and `charon-enr-private-key`
- Docker running
- `jq` installed

## For Remaining Operators

Automates the complete workflow for operators staying in the cluster:

```bash
./scripts/edit/replace-operator/remaining-operator.sh \
    --new-enr "enr:-..." \
    --old-enr "enr:-..."
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--new-enr <enr>` | Yes | ENR of the new operator |
| `--old-enr <enr>` | Yes | ENR of the operator being replaced |
| `--skip-export` | No | Skip ASDB export if already done |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

### Workflow

1. **Export ASDB** - Export anti-slashing database from running VC
2. **Run ceremony** - Execute `charon alpha edit replace-operator` with new ENR
3. **Update ASDB** - Replace pubkeys in exported ASDB to match new cluster-lock
4. **Stop containers** - Stop charon and VC
5. **Backup and replace** - Backup old cluster-lock, install new one
6. **Import ASDB** - Import updated anti-slashing database
7. **Print restart commands** - Display commands to start containers after waiting ~2 epochs

## For New Operators

Two-step workflow for the new operator joining the cluster.

**Step 1:** Generate ENR and share with remaining operators:

```bash
./scripts/edit/replace-operator/new-operator.sh --generate-enr
```

**Step 2:** After receiving cluster-lock from remaining operators:

```bash
./scripts/edit/replace-operator/new-operator.sh --cluster-lock ./received-cluster-lock.json
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--cluster-lock <path>` | No | Path to new cluster-lock.json |
| `--generate-enr` | No | Generate new ENR private key |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

## Related

- [Add-Validators Workflow](../add-validators/README.md)
- [Add-Operators Workflow](../add-operators/README.md)
- [Remove-Operators Workflow](../remove-operators/README.md)
- [Recreate-Private-Keys Workflow](../recreate-private-keys/README.md)
- [Anti-Slashing DB Scripts](../vc/README.md)
- [Obol Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/replace-operator)
