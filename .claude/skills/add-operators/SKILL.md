---
name: add-operators
description: Add new operators to an existing Charon distributed validator cluster
user-invokable: true
---

# Add Operators

Expand a Charon cluster by adding new operators. This is a coordinated operation involving both existing and new operators.

## Prerequisites

Read `scripts/edit/add-operators/README.md` for full details if needed.

Common prerequisites:
1. `.env` file exists with `NETWORK` and `VC` variables set
2. Docker is running

## Role Selection

Ask the user: **"Are you an existing operator in the cluster, or a new operator joining?"**

### If Existing Operator

**Script**: `scripts/edit/add-operators/existing-operator.sh`

**Additional prerequisites**:
- `.charon/cluster-lock.json` and `.charon/validator_keys/` must exist
- VC container must be running (needed for ASDB export)

**Arguments to gather**:
- `--new-operator-enrs`: Comma-separated ENRs of the new operators joining
- Whether to use `--dry-run` first

**Run**:
```bash
./scripts/edit/add-operators/existing-operator.sh \
    --new-operator-enrs "enr:-...,enr:-..." \
    [--dry-run]
```

The script will export the anti-slashing database, run the P2P ceremony, update keys, and provide restart instructions. After completion, remind the user to **wait ~2 epochs before restarting** containers.

### If New Operator

**Script**: `scripts/edit/add-operators/new-operator.sh`

This is a **two-step process**:

#### Step 1: Generate ENR

Ask if the user needs to generate an ENR (first time setup):

```bash
./scripts/edit/add-operators/new-operator.sh --generate-enr
```

This creates `.charon/charon-enr-private-key` and displays the ENR. Tell the user to **share this ENR with the existing operators**.

#### Step 2: Join the Ceremony

After the existing operators have the ENR, gather:
- `--new-operator-enrs`: Comma-separated ENRs of ALL new operators (including their own)
- `--cluster-lock`: Path to the `cluster-lock.json` received from existing operators
- Whether to use `--dry-run` first

```bash
./scripts/edit/add-operators/new-operator.sh \
    --new-operator-enrs "enr:-...,enr:-..." \
    --cluster-lock ./received-cluster-lock.json \
    [--dry-run]
```

Remind the user that **all operators (existing AND new) must participate simultaneously** in the P2P ceremony.
