# Replace-Operator Integration Tests

Integration tests for `new-operator.sh` and `remaining-operator.sh` scripts.

## Overview

These tests validate the replace-operator scripts without running actual Docker containers or the charon ceremony. The focus is on:

- **Argument parsing and validation**
- **Prerequisite checks** (`.env`, `.charon/`, cluster-lock, ENR key)
- **Dry-run output** for all workflow steps
- **Error messages** for missing/invalid inputs

## Running Tests

```bash
./scripts/edit/replace-operator/test/test_replace_operator.sh
```

Expected output: All 21 tests should pass in under 5 seconds.

## What's NOT Tested

- **Actual Docker operations** - Docker commands are mocked
- **Charon ceremony** - Would require actual cluster coordination
- **ASDB export/import** - Tested separately in `scripts/edit/vc/test/`
- **Container orchestration** - Would require running services
