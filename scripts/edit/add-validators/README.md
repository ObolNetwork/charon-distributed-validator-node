# Add-Validators Script

Script to automate the [add-validators ceremony](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-validators) for Charon distributed validators.

## Overview

This script helps operators add new validators to an existing distributed validator cluster. This is useful for:

- **Expanding capacity**: Add more validators without creating a new cluster
- **Scaling operations**: Grow your staking operation with existing operators

**Important**: This is a coordinated ceremony. All operators must run this script simultaneously to complete the process.

> **Warning**: This is an alpha feature in Charon and is not yet recommended for production use.

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- `.charon` directory with `cluster-lock.json`
- Docker running
- `jq` installed
- **All operators must participate in the ceremony**

## Usage

All operators must run this script simultaneously:

```bash
./scripts/edit/add-validators/add-validators.sh \
    --num-validators 10 \
    --withdrawal-addresses 0x123...abc \
    --fee-recipient-addresses 0x456...def
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--num-validators <N>` | Yes | Number of validators to add |
| `--withdrawal-addresses <addr>` | Yes | Withdrawal address(es), comma-separated for multiple |
| `--fee-recipient-addresses <addr>` | Yes | Fee recipient address(es), comma-separated |
| `--unverified` | No | Skip key verification (for remote KeyManager) |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

## Workflow

The script performs the following steps:

1. **Check prerequisites** - Verify environment, cluster-lock, and detect running containers
2. **Run ceremony** - P2P coordinated add-validators ceremony with all operators
3. **Stop containers** - Stop charon and VC (only if they were running)
4. **Backup and replace** - Backup current `.charon/` to `./backups/`, install new configuration
5. **Restart containers** - Start charon and VC (only if they were running before)

## Related

- [Add-Operators Workflow](../add-operators/README.md)
- [Remove-Operators Workflow](../remove-operators/README.md)
- [Recreate-Private-Keys Workflow](../recreate-private-keys/README.md)
- [Replace-Operator Workflow](../replace-operator/README.md)
- [Anti-Slashing DB Scripts](../vc/README.md)
- [Obol Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-validators)
