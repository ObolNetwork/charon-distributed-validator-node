# Cluster Edit Automation Scripts

This directory contains automation scripts to help node operators perform cluster editing operations for Charon distributed validators. The scripts currently support the **replace-operator** ceremony.

## Directory Structure

```
scripts/edit/
├── lib/
│   └── update-anti-slashing-db.sh    # Library script for ASDB key translation
└── <vc_type>/                         # VC-specific scripts (e.g., lodestar/)
    ├── export_asdb.sh                 # Export anti-slashing database
    ├── import_asdb.sh                 # Import anti-slashing database
    └── replace_operator.sh            # Main orchestration script
```

## Prerequisites

Before using these scripts, ensure:

1. **Environment Configuration**: Your `.env` file must exist and contain:
   - `NETWORK` - The Ethereum network (e.g., `mainnet`, `hoodi`, `sepolia`)

2. **Validator Client Profile**: You must be using the `vc-lodestar` profile:
   - Set `VC=vc-lodestar` in your `.env` file
   - Ensure the profile is active in your docker compose setup

3. **Required Tools**:
   - `docker` and `docker compose`
   - `jq` - JSON processor
   - `zip` - For creating backups

4. **Directory Structure**: Run scripts from the repository root where:
   - `.charon/` directory exists
   - `docker-compose.yml` is present

## Replace-Operator Workflow

The replace-operator ceremony allows a cluster to swap one operator for another without changing validator public keys. This requires coordination between all continuing operators and the new operator.

### For Continuing Operators

Continuing operators are existing cluster members who will remain in the cluster after the replacement.

#### CLI Mode

```bash
./scripts/edit/lodestar/replace_operator.sh \
  --role continuing \
  --old-enr enr:-JG4QH... \
  --new-enr enr:-JG4QK...
```

#### Interactive Mode

```bash
./scripts/edit/lodestar/replace_operator.sh
```

The script will prompt for:
- Your role (select "continuing")
- Old operator ENR
- New operator ENR

#### What Happens

1. **Backup**: Creates `.charon-before-replace-operator-TIMESTAMP.zip`
2. **Export ASDB**: Prompts you to run `./scripts/edit/lodestar/export_asdb.sh`
3. **Ceremony**: Executes the replace-operator ceremony with other operators
4. **Update ASDB**: Translates validator keys in the exported database
5. **Instructions**: Displays steps to activate the new configuration

### For New Operators

New operators are joining the cluster to replace an existing operator.

#### CLI Mode

```bash
./scripts/edit/lodestar/replace_operator.sh \
  --role new \
  --old-enr enr:-JG4QH... \
  --new-enr enr:-JG4QK... \
  --cluster-lock-file ./cluster-lock.json
```

#### Interactive Mode

```bash
./scripts/edit/lodestar/replace_operator.sh
```

The script will prompt for:
- Your role (select "new")
- Old operator ENR
- New operator ENR  
- Path to your `cluster-lock.json` file

#### What Happens

1. **Backup**: Creates `.charon-before-replace-operator-TIMESTAMP.zip`
2. **Ceremony**: Executes the replace-operator ceremony with other operators
3. **Instructions**: Displays steps to activate the new configuration

**Note**: New operators do NOT export/import anti-slashing databases since they start fresh.

## Individual Script Usage

While `replace_operator.sh` orchestrates the full workflow, you can also run individual scripts:

### Export Anti-Slashing Database

```bash
./scripts/edit/lodestar/export_asdb.sh [--data-dir ./data/lodestar] [--output-file ./asdb-export/slashing-protection.json]
```

**Requirements**:
- vc-lodestar container must be running
- `.env` file with `NETWORK` variable

**Output**: EIP-3076 format JSON file containing slashing protection data

### Import Anti-Slashing Database

```bash
./scripts/edit/lodestar/import_asdb.sh [--input-file ./asdb-export/slashing-protection.json] [--data-dir ./data/lodestar]
```

**Requirements**:
- vc-lodestar container must be STOPPED
- Valid EIP-3076 JSON file
- `.env` file with `NETWORK` variable

**Effect**: Imports slashing protection data into Lodestar validator client

### Ceremony timeout or failure

If the ceremony fails or times out:

1. **Check coordination**: Ensure all operators executed simultaneously
2. **Check network**: Verify all operators can reach ceremony relays
3. **Check ENRs**: Confirm old and new operator ENRs are correct
4. **Rollback**: Restore from backup if needed:
   ```bash
   rm -rf .charon
   unzip .charon-before-replace-operator-*.zip
   rm -rf ./output
   ```

## Additional Resources

- [Obol Replace-Operator Documentation](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/replace-operator)
- [Charon Edit Commands](https://docs.obol.org/next/advanced-and-troubleshooting/advanced/)
- [EIP-3076 Slashing Protection Interchange Format](https://eips.ethereum.org/EIPS/eip-3076)

## Future VC Support

To add support for other validator clients (Nimbus, Prysm, Teku):

1. Create a new directory: `scripts/edit/<vc_type>/`
2. Implement `export_asdb.sh` for the client's slashing protection format
3. Implement `import_asdb.sh` for the client's import mechanism
4. Copy and adapt `replace_operator.sh` for the client's service name
5. Update this README with client-specific instructions

