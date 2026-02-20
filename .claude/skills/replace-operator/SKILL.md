---
name: replace-operator
description: Replace a single operator in a Charon distributed validator cluster
user-invokable: true
---

# Replace Operator

Replace a single operator in a Charon cluster with a new one. All participating operators (remaining + new) run a `charon alpha edit replace-operator` ceremony together (P2P via relay). The new operator must receive the current cluster-lock.json before the ceremony begins.

## Prerequisites

Read `scripts/edit/replace-operator/README.md` for full details if needed.

Common prerequisites:
1. `.env` file exists with `NETWORK` and `VC` variables set
2. `.charon` directory with `cluster-lock.json` and `charon-enr-private-key`
3. Docker is running
4. `jq` installed

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

After completion, the script will print commands to start containers manually. Remind the user to **wait ~2 epochs before starting** containers.

### If New Operator

**Script**: `scripts/edit/replace-operator/new-operator.sh`

This is a **three-step process**:

#### Step 1: Generate ENR

Ask if the user needs to generate an ENR:

```bash
./scripts/edit/replace-operator/new-operator.sh --generate-enr
```

This creates `.charon/charon-enr-private-key` and displays the ENR. Tell the user to **share this ENR with the remaining operators**.

#### Step 2: Run the Ceremony

After receiving the current `cluster-lock.json` from remaining operators (BEFORE the ceremony):
- `--cluster-lock`: Path to the received `cluster-lock.json`
- `--old-enr`: ENR of the operator being replaced
- Whether to use `--dry-run` first

```bash
./scripts/edit/replace-operator/new-operator.sh \
    --cluster-lock ./received-cluster-lock.json \
    --old-enr "enr:-..." \
    [--dry-run]
```

The new operator runs this **at the same time** as the remaining operators run their ceremony. All operators must participate together.

#### Step 3: Install New Cluster Lock

After the ceremony completes, install the new cluster-lock:

```bash
./scripts/edit/replace-operator/new-operator.sh \
    --install-lock ./output/cluster-lock.json \
    [--dry-run]
```

The script will verify the ENR is present in the cluster-lock, install the configuration, and print commands to start containers manually. Note: the new operator does NOT have slashing protection history (fresh start).
