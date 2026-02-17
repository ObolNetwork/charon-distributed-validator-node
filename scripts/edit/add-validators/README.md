# Add-Validators Script

Script to automate the [add-validators ceremony](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-validators) for Charon distributed validators.

## Overview

This script helps operators add new validators to an existing distributed validator cluster. This is useful for:

- **Expanding capacity**: Add more validators without creating a new cluster
- **Scaling operations**: Grow your staking operation with existing operators

**Important**: This is a coordinated ceremony. All operators must run this script simultaneously to complete the process.

> ⚠️ This is an alpha feature in Charon and is not yet recommended for production use.

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables set
- `.charon` directory with `cluster-lock.json`
- Docker running
- **Charon and VC must be RUNNING** during the ceremony
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
| `--withdrawal-addresses <addr>` | No | Withdrawal address(es), comma-separated for multiple |
| `--fee-recipient-addresses <addr>` | No | Fee recipient address(es), comma-separated |
| `--unverified` | No | Skip key verification (for remote KeyManager) |
| `--dry-run` | No | Preview without executing |
| `-h, --help` | No | Show help message |

### Examples

```bash
# Add 10 validators with same addresses for all
./scripts/edit/add-validators/add-validators.sh \
    --num-validators 10 \
    --withdrawal-addresses 0x123...abc \
    --fee-recipient-addresses 0x456...def

# Add validators without key verification (remote KeyManager)
./scripts/edit/add-validators/add-validators.sh \
    --num-validators 5 \
    --withdrawal-addresses 0x123...abc \
    --fee-recipient-addresses 0x456...def \
    --unverified

# Preview what would happen
./scripts/edit/add-validators/add-validators.sh \
    --num-validators 5 \
    --withdrawal-addresses 0x123...abc \
    --dry-run
```

## Workflow

The script performs the following steps:

1. **Check prerequisites** - Verify environment, cluster-lock, and running containers
2. **Run ceremony** - P2P coordinated add-validators ceremony with all operators
3. **Stop containers** - Stop charon and VC
4. **Backup and replace** - Backup current `.charon/` to `./backups/`, install new configuration
5. **Restart containers** - Start charon and VC with new configuration

## After the Ceremony

1. **Wait for threshold** - Once threshold operators complete their upgrades, new validators will begin participating
2. **Generate deposits** - New validator deposit data is available in `.charon/deposit-data.json`
3. **Activate validators** - Submit deposits to activate new validators on the beacon chain

## Using --unverified Mode

If your validator keys are stored remotely (e.g., in a KeyManager) and Charon cannot access them, use the `--unverified` flag. This skips key verification during the ceremony.

**Important**: When using cluster artifacts created with `--unverified`:
- You must start `charon run` with the `--no-verify` flag
- Or set `CHARON_NO_VERIFY=true` in your `.env` file

## Current Limitations

- The new cluster configuration will not be reflected on the Obol Launchpad
- The new cluster will have a new cluster hash (different observability identifier)
- All operators must participate; no partial participation option

## Related

- [Recreate-Private-Keys Workflow](../recreate-private-keys/README.md)
- [Replace-Operator Workflow](../replace-operator/README.md)
- [Obol Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-validators)
