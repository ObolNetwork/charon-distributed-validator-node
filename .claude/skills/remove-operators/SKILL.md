---
name: remove-operators
description: Remove operators from an existing Charon distributed validator cluster
user-invokable: true
---

# Remove Operators

Remove one or more operators from a Charon cluster. Whether removed operators need to participate depends on fault tolerance.

## Prerequisites

Read `scripts/edit/remove-operators/README.md` for full details if needed.

Common prerequisites:
1. `.env` file exists with `NETWORK` and `VC` variables set
2. `.charon/cluster-lock.json` exists
3. Docker is running

## Fault Tolerance Context

Explain to the user:
- Fault tolerance `f = operators - threshold`
- If removing **<= f** operators: removed operators do NOT need to participate (they just stop their nodes)
- If removing **> f** operators: removed operators MUST also participate using `removed-operator.sh`

## Role Selection

Ask the user: **"Are you a remaining operator (staying in the cluster) or a removed operator (leaving the cluster)?"**

### If Remaining Operator

**Script**: `scripts/edit/remove-operators/remaining-operator.sh`

**Additional prerequisites**:
- `.charon/validator_keys/` must exist
- The script will automatically stop the VC container for ASDB export

**Arguments to gather**:
- `--operator-enrs-to-remove`: Comma-separated ENRs of operators being removed
- `--participating-operator-enrs` (only if removal exceeds fault tolerance): Comma-separated ENRs of ALL participating operators
- `--new-threshold` (optional): Override the default threshold (defaults to ceil(n * 2/3))
- Whether to use `--dry-run` first

**Run**:
```bash
./scripts/edit/remove-operators/remaining-operator.sh \
    --operator-enrs-to-remove "enr:-...,enr:-..." \
    [--participating-operator-enrs "enr:-...,enr:-..."] \
    [--new-threshold N] \
    [--dry-run]
```

After completion, the script will print commands to start containers manually. Remind the user to **wait ~2 epochs before starting** containers.

### If Removed Operator

**Script**: `scripts/edit/remove-operators/removed-operator.sh`

This is **only needed when the removal exceeds fault tolerance**. If within fault tolerance, the removed operator simply stops their node.

**Additional prerequisites**:
- `.charon/charon-enr-private-key` must exist
- `.charon/validator_keys/` must exist

**Arguments to gather**:
- `--operator-enrs-to-remove`: Comma-separated ENRs of operators being removed
- `--participating-operator-enrs`: Comma-separated ENRs of ALL participating operators (must include your own ENR)
- `--new-threshold` (optional): Override the default threshold
- Whether to use `--dry-run` first

**Run**:
```bash
./scripts/edit/remove-operators/removed-operator.sh \
    --operator-enrs-to-remove "enr:-...,enr:-..." \
    --participating-operator-enrs "enr:-...,enr:-..." \
    [--new-threshold N] \
    [--dry-run]
```

The script will participate in the ceremony and then stop your charon and VC containers. No ASDB operations are needed since you're leaving the cluster.
