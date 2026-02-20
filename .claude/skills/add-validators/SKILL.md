---
name: add-validators
description: Add new validators to an existing Charon distributed validator cluster
user-invokable: true
---

# Add Validators

Add new validators to an existing Charon distributed validator cluster. All operators must run this simultaneously as it requires a P2P ceremony.

## Prerequisites

Before running, verify:
1. `.env` file exists with `NETWORK` and `VC` variables set
2. `.charon/cluster-lock.json` exists
3. Docker is running
4. `jq` is installed

Read `scripts/edit/add-validators/README.md` for full details if needed.

## Gather Arguments

Ask the user for the following required arguments using AskUserQuestion:

1. **Number of validators** (`--num-validators`): How many new validators to add (positive integer)
2. **Withdrawal addresses** (`--withdrawal-addresses`): Comma-separated Ethereum withdrawal address(es)
3. **Fee recipient addresses** (`--fee-recipient-addresses`): Comma-separated fee recipient address(es)

Also ask whether they want to:
- Run with `--dry-run` first to preview the operation
- Use `--unverified` flag (skip key verification, used for remote KeyManager API setups)

## Execution

Run the script from the repository root:

```bash
./scripts/edit/add-validators/add-validators.sh \
    --num-validators <N> \
    --withdrawal-addresses <addrs> \
    --fee-recipient-addresses <addrs> \
    [--unverified] [--dry-run]
```

The script will:
1. Validate prerequisites
2. Display current cluster info (operators, validators)
3. Run a P2P ceremony (all operators must participate simultaneously)
4. Stop containers if they were running
5. Backup `.charon/` to `./backups/`
6. Install new configuration
7. Print commands to start containers manually

Remind the user that **all operators must run this script at the same time** for the P2P ceremony to succeed.
