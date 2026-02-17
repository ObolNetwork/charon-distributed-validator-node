# Anti-Slashing Database Scripts

Scripts to export, import, and update validator anti-slashing databases (ASDB) in [EIP-3076](https://eips.ethereum.org/EIPS/eip-3076) format for Charon distributed validators.

## Overview

When performing cluster edit operations (replace-operator, recreate-private-keys), the anti-slashing database must be exported, updated with new pubkeys, and re-imported to prevent slashing violations. These scripts automate that process across all supported validator clients.

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- Docker running
- `jq` installed (for `update-anti-slashing-db.sh`)

## Scripts

### Router Scripts

| Script | Description |
|--------|-------------|
| `export_asdb.sh` | Routes to the appropriate VC-specific export script based on `VC` env var |
| `import_asdb.sh` | Routes to the appropriate VC-specific import script based on `VC` env var |

Usage:

```bash
# Export ASDB from running VC container
VC=vc-lodestar ./scripts/edit/vc/export_asdb.sh --output-file ./asdb-export/slashing-protection.json

# Import ASDB into stopped VC container
VC=vc-lodestar ./scripts/edit/vc/import_asdb.sh --input-file ./asdb-export/slashing-protection.json
```

### Update Anti-Slashing DB

Updates pubkeys in an EIP-3076 file by mapping them between source and target cluster-lock files.

```bash
./scripts/edit/vc/update-anti-slashing-db.sh <eip3076-file> <source-cluster-lock> <target-cluster-lock>
```

### Supported Validator Clients

Each client has its own `export_asdb.sh` and `import_asdb.sh` in a subdirectory:

| Client | Directory | Export requires | Import requires |
|--------|-----------|-----------------|-----------------|
| Lodestar | `lodestar/` | Container running | Container stopped |
| Prysm | `prysm/` | Container running | Container stopped |
| Teku | `teku/` | Container running | Container stopped |
| Nimbus | `nimbus/` | Container running | Container stopped |

## Testing

See [test/README.md](test/README.md) for integration tests.

## Related

- [Replace-Operator Workflow](../replace-operator/README.md)
- [Recreate-Private-Keys Workflow](../recreate-private-keys/README.md)
- [Add-Validators Workflow](../add-validators/README.md)
