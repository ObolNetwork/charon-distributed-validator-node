---
name: replace-operator
description: Replace a single operator in a Charon distributed validator cluster
user-invokable: true
---

# Replace Operator

Replace a single operator in a Charon cluster with a new one. This is a non-P2P local operation (no coordinated ceremony required).

## Prerequisites

Read `scripts/edit/replace-operator/README.md` for full details if needed.

Common prerequisites:
1. `.env` file exists with `NETWORK` and `VC` variables set
2. Docker is running

## Role Selection

Ask the user: **"Are you a remaining operator (performing the replacement) or the new operator joining as a replacement?"**

### If Remaining Operator

**Script**: `scripts/edit/replace-operator/remaining-operator.sh`

**Additional prerequisites**:
- `.charon/cluster-lock.json` and `.charon/charon-enr-private-key` must exist
- The script will automatically stop the VC container for ASDB export (unless `--skip-export` is used)

**Arguments to gather**:
- `--new-enr`: ENR of the new replacement operator
- `--old-enr`: ENR of the operator being replaced
- `--skip-export` (optional): Skip ASDB export if already done
- Whether to use `--dry-run` first

**Run**:
```bash
./scripts/edit/replace-operator/remaining-operator.sh \
    --new-enr "enr:-..." \
    --old-enr "enr:-..." \
    [--skip-export] \
    [--dry-run]
```

After completion, the script will output the new `cluster-lock.json`. Remind the user to **share the new cluster-lock.json with the new operator** and to **wait ~2 epochs before restarting** containers.

### If New Operator

**Script**: `scripts/edit/replace-operator/new-operator.sh`

This is a **two-step process**:

#### Step 1: Generate ENR

Ask if the user needs to generate an ENR:

```bash
./scripts/edit/replace-operator/new-operator.sh --generate-enr
```

This creates `.charon/charon-enr-private-key` and displays the ENR. Tell the user to **share this ENR with the remaining operators**.

#### Step 2: Install Cluster Lock

After receiving the new `cluster-lock.json` from remaining operators:
- `--cluster-lock`: Path to the received `cluster-lock.json`
- Whether to use `--dry-run` first

```bash
./scripts/edit/replace-operator/new-operator.sh \
    --cluster-lock ./received-cluster-lock.json \
    [--dry-run]
```

The script will verify the ENR is present in the cluster-lock, install the configuration, and start charon and VC containers. Note: the new operator does NOT have slashing protection history (fresh start).
