# Recreate-Private-Keys Integration Tests

Integration tests for `recreate-private-keys.sh` script.

## Overview

These tests validate the recreate-private-keys script without running actual Docker containers or the ceremony. The focus is on:

- **Argument parsing and validation**
- **Prerequisite checks** (`.env`, `.charon/`, cluster-lock, validator_keys)
- **Dry-run output** for all workflow steps
- **Error messages** for missing/invalid inputs

## Running Tests

```bash
./scripts/edit/recreate-private-keys/test/test_recreate_private_keys.sh
```

Expected output: All tests should pass in under 5 seconds.

## What's NOT Tested

- **Actual Docker operations** - Docker commands are mocked
- **Charon ceremony** - Would require actual cluster coordination with all operators
- **Container orchestration** - Would require running services
