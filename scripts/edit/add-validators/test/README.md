# Add-Validators Integration Tests

Integration tests for `add-validators.sh` script.

## Overview

These tests validate the add-validators script without running actual Docker containers or the ceremony. The focus is on:

- **Argument parsing and validation**
- **Prerequisite checks** (`.env`, `.charon/`, cluster-lock)
- **Dry-run output** for all workflow steps
- **Error messages** for missing/invalid inputs

## Running Tests

```bash
./scripts/edit/add-validators/test/test_add_validators.sh
```

Expected output: All tests should pass in under 5 seconds.

## What's NOT Tested

- **Actual Docker operations** - Docker commands are mocked
- **Charon ceremony** - Would require actual cluster coordination with all operators
- **Container orchestration** - Would require running services

## Test Structure

```
test/
├── README.md              # This file
├── test_add_validators.sh # Main test script
├── fixtures/              # Test fixtures
│   ├── .env.test          # Test environment file
│   └── .charon/           # Mock .charon directory
│       ├── cluster-lock.json
│       └── charon-enr-private-key
└── data/                  # Test runtime data (git-ignored)
    ├── backup/            # Backed up repo files during test
    └── mock-bin/          # Mock docker command
```

## Adding New Tests

1. Add a new test function following the naming convention `test_*`
2. Use the assertion helpers: `assert_exit_code`, `assert_output_contains`, `assert_output_not_contains`
3. Register the test in the `main()` function using `run_test`
