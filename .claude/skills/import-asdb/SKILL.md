---
name: import-asdb
description: Import an anti-slashing database (EIP-3076) into the validator client
user-invokable: true
---

# Import Anti-Slashing Database

Import an EIP-3076 anti-slashing database into the validator client. The VC container must be stopped.

## Prerequisites

1. `.env` file exists with `VC` variable set
2. VC container must be **stopped**

Read `scripts/edit/vc/README.md` for full details if needed.

## Gather Arguments

Ask the user for:
- `--input-file`: Path to the JSON file to import (e.g., `./asdb-export/slashing-protection.json`)

## Execution

```bash
./scripts/edit/vc/import_asdb.sh --input-file <path>
```

The `VC` variable is read from `.env` automatically. The script routes to the appropriate VC-specific import implementation (lodestar, teku, prysm, or nimbus).
