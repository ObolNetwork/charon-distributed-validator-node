# Recreate-Private-Keys Script

Script to automate the [recreate-private-keys ceremony](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/recreate-private-keys) for Charon distributed validators.

## Overview

This script helps operators recreate validator private key shares while keeping the same validator public keys. This is useful for:

- **Security concerns**: If private key shares may have been compromised
- **Key rotation**: As part of regular security practices
- **Recovery**: After a security incident to refresh key material

**Important**: This operation maintains the same validator public keys, so validators remain registered on the beacon chain without any changes. Only the underlying private key shares held by operators are refreshed.

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- `.charon` directory with `cluster-lock.json` and `validator_keys`
- Docker running
- **All operators must participate in the ceremony**

## Usage

All operators must run this script simultaneously:

```bash
./scripts/edit/recreate-private-keys/recreate-private-keys.sh
```

The script will:
1. Export the anti-slashing database from the validator client
2. Run the recreate-private-keys ceremony (P2P coordinated with all operators)
3. Update the ASDB pubkeys to match new key shares
4. Stop charon and VC containers
5. Backup current `.charon` directory to `./backups/`
6. Move new keys from `./output/` to `.charon/`
7. Import the updated anti-slashing database
8. Restart containers

## Options

| Option | Required | Description |
|--------|----------|-------------|
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

## Current Limitations

- The new cluster configuration will not be reflected on the Launchpad
- The new cluster will have a new cluster hash (different observability identifier)
- All operators must participate; no partial participation option
- All operators must have their current validator private key shares

## Related

- [Replace-Operator Workflow](../replace-operator/README.md)
- [Anti-Slashing DB Scripts](../vc/README.md)
- [Obol Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/recreate-private-keys)
