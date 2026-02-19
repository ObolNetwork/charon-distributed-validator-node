---
name: export-asdb
description: Export the anti-slashing database (EIP-3076) from the running validator client
user-invokable: true
---

# Export Anti-Slashing Database

Export the EIP-3076 anti-slashing database from the currently running validator client. The VC container must be running.

## Prerequisites

1. `.env` file exists with `VC` variable set
2. VC container must be **running**

Read `scripts/edit/vc/README.md` for full details if needed.

## Gather Arguments

Ask the user for:
- `--output-file`: Path to write the exported JSON file (e.g., `./asdb-export/slashing-protection.json`)

## Execution

```bash
./scripts/edit/vc/export_asdb.sh --output-file <path>
```

The `VC` variable is read from `.env` automatically. The script routes to the appropriate VC-specific export implementation (lodestar, teku, prysm, or nimbus).
