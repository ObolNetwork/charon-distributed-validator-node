# Integration Tests for ASDB Export/Import Scripts

These tests verify export/import scripts for various VC types work correctly with test data.

## Prerequisites

- Docker must be running
- No `.charon` folder required (test uses fixtures)

## Running Tests

```bash
# Lodestar VC test
# (for other VC types the usage is identical)
./scripts/edit/vc/test/test_lodestar_asdb.sh
```

## ⚠️ Test Isolation

The test uses isolated data directories within `scripts/edit/vc/test/data/` to avoid any interference with production data in `data/`.

## Test Flow

1. Starts vc-lodestar container (no charon dependency)
2. Imports sample slashing protection data from fixtures
3. Exports slashing protection via `export_asdb.sh`
4. Transforms pubkeys via `update-anti-slashing-db.sh`
5. Re-imports updated data via `import_asdb.sh`

## Test Artifacts

After running, inspect results in `scripts/edit/vc/test/output/`:
- `exported-asdb.json` - Original export
- `updated-asdb.json` - After pubkey transformation
