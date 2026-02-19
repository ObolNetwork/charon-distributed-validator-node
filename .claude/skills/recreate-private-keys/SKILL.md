---
name: recreate-private-keys
description: Recreate private key shares for a Charon cluster while keeping the same validator public keys
user-invokable: true
---

# Recreate Private Keys

Refresh private key shares held by operators while keeping the same validator public keys. Validators stay registered on the beacon chain - only the operator key shares change. All operators must participate simultaneously.

## Use Cases

- Security concerns: private key shares may have been compromised
- Key rotation: regular security practice
- Recovery: after a security incident

## Prerequisites

Before running, verify:
1. `.env` file exists with `NETWORK` and `VC` variables set
2. `.charon/cluster-lock.json` and `.charon/validator_keys/` exist
3. Docker is running
4. VC container must be running (for ASDB export)

Read `scripts/edit/recreate-private-keys/README.md` for full details if needed.

## Execution

Ask the user whether they want to run with `--dry-run` first to preview the operation.

```bash
./scripts/edit/recreate-private-keys/recreate-private-keys.sh [--dry-run]
```

The script will:
1. Validate prerequisites
2. Export the anti-slashing database from the running VC
3. Run a P2P ceremony (all operators must participate simultaneously)
4. Update ASDB pubkeys to match new key shares
5. Stop containers
6. Backup `.charon/` to `./backups/`
7. Install new key shares
8. Import updated ASDB

After completion, remind the user to **wait ~2 epochs before restarting** containers.

Remind the user that **all operators must run this script at the same time** for the P2P ceremony to succeed.
