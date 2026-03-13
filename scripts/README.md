# Cluster Edit Automation Scripts

Automation scripts for Charon distributed validator cluster editing operations.

## Documentation

- [Charon Edit Commands](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/)
- [EIP-3076 Slashing Protection Interchange Format](https://eips.ethereum.org/EIPS/eip-3076)

## Scripts

| Directory | Description |
|-----------|-------------|
| [edit/add-validators/](edit/add-validators/README.md) | Add new validators to an existing cluster |
| [edit/recreate-private-keys/](edit/recreate-private-keys/README.md) | Refresh private key shares while keeping the same validator public keys |
| [edit/add-operators/](edit/add-operators/README.md) | Expand the cluster by adding new operators |
| [edit/remove-operators/](edit/remove-operators/README.md) | Remove operators from the cluster |
| [edit/replace-operator/](edit/replace-operator/README.md) | Replace a single operator in a cluster |
| [edit/vc/](edit/vc/README.md) | Export/import/update anti-slashing databases (EIP-3076) |
| [edit/test/](edit/test/README.md) | E2E integration tests for all edit scripts |

## Prerequisites

- `.env` file with `NETWORK` and `VC` variables
- Docker and `docker compose`
- `jq`

