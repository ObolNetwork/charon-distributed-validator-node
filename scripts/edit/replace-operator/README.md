# Replace-Operator Scripts

Scripts to automate the [replace-operator workflow](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/replace-operator) for Charon distributed validators.

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- Docker running
- `jq` installed

## For Remaining Operators

Automates the complete workflow for operators staying in the cluster:

```bash
./scripts/edit/replace-operator/remaining-operator.sh \
    --new-enr "enr:-..." \
    --operator-index 2
```

**Options:**
- `--new-enr <enr>` - ENR of the new operator (required)
- `--operator-index <N>` - Index of operator being replaced (required)
- `--skip-export` - Skip ASDB export if already done
- `--skip-ceremony` - Skip ceremony if cluster-lock already generated
- `--dry-run` - Preview without executing

## For New Operators

**Step 1:** Generate ENR and share with remaining operators:

```bash
./scripts/edit/replace-operator/new-operator.sh --generate-enr
```

**Step 2:** After receiving cluster-lock from remaining operators:

```bash
# curl -o received-cluster-lock.json https://example.com/cluster-lock.json
./scripts/edit/replace-operator/new-operator.sh --cluster-lock ./received-cluster-lock.json
```

**Options:**
- `--cluster-lock <path>` - Path to new cluster-lock.json
- `--generate-enr` - Generate new ENR private key
- `--dry-run` - Preview without executing

## Testing

See [test/README.md](test/README.md) for integration tests.
