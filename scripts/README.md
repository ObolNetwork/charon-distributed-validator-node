# Cluster Edit Automation Scripts

Automation scripts for Charon distributed validator cluster editing operations.

## Documentation

- [Obol Replace-Operator Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/replace-operator)
- [Charon Edit Commands](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/)
- [EIP-3076 Slashing Protection Interchange Format](https://eips.ethereum.org/EIPS/eip-3076)

## Scripts

| Directory | Description |
|-----------|-------------|
| [edit/replace-operator/](edit/replace-operator/README.md) | Replace an operator in a cluster |
| [edit/vc/](edit/vc/) | Export/import anti-slashing database for various VCs |

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables
- Docker and `docker compose`
- `jq`

