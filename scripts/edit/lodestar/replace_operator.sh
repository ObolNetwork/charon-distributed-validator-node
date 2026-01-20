#!/usr/bin/env bash

# Script to orchestrate the replace-operator ceremony for Charon distributed validators.
#
# This script guides node operators through the complete replace-operator workflow:
# - For continuing operators: export ASDB → ceremony → update ASDB → import
# - For new operators: ceremony only (no ASDB operations)
#
# Usage: replace_operator.sh [OPTIONS]
#
# Required Options (or will be prompted):
#   --role <continuing|new>        Your role in the cluster (continuing or new operator)
#   --old-enr <enr>                ENR of the operator being replaced
#   --new-enr <enr>                ENR of the new operator
#
# Optional for new operators:
#   --cluster-lock-file <path>     Path to cluster-lock.json (required for new operators)
#
# Optional directories:
#   --output-dir <path>            Output directory for new cluster config (default: ./output)
#   --backup-file <path>           Backup zip filename (default: .charon-before-replace-operator-TIMESTAMP.zip)
#   --asdb-dir <path>              Directory for ASDB export/import (default: ./asdb-export)
#
# Requirements:
#   - .charon/ directory must exist
#   - Output directory must NOT exist
#   - docker and docker compose must be available
#   - zip command must be available

set -euo pipefail

# Default values
ROLE=""
OLD_ENR=""
NEW_ENR=""
CLUSTER_LOCK_FILE=""
OUTPUT_DIR="./output"
BACKUP_FILE=".charon-before-replace-operator-$(date +%Y%m%d-%H%M%S).zip"
ASDB_DIR="./asdb-export"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --role)
            ROLE="$2"
            shift 2
            ;;
        --old-enr)
            OLD_ENR="$2"
            shift 2
            ;;
        --new-enr)
            NEW_ENR="$2"
            shift 2
            ;;
        --cluster-lock-file)
            CLUSTER_LOCK_FILE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --backup-file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --asdb-dir)
            ASDB_DIR="$2"
            shift 2
            ;;
        -h|--help)
            grep "^#" "$0" | grep -v "#!/usr/bin/env" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Interactive prompts for missing required values
if [ -z "$ROLE" ]; then
    echo "What is your role in this cluster?"
    echo "  1) continuing - I am an existing operator staying in the cluster"
    echo "  2) new - I am the new operator joining the cluster"
    read -p "Enter choice (1 or 2): " role_choice
    case $role_choice in
        1) ROLE="continuing" ;;
        2) ROLE="new" ;;
        *)
            echo "Error: Invalid choice" >&2
            exit 1
            ;;
    esac
fi

# Validate role
if [[ "$ROLE" != "continuing" && "$ROLE" != "new" ]]; then
    echo "Error: Role must be 'continuing' or 'new'" >&2
    exit 1
fi

if [ -z "$OLD_ENR" ]; then
    read -p "Enter the ENR of the operator being replaced: " OLD_ENR
fi

if [ -z "$NEW_ENR" ]; then
    read -p "Enter the ENR of the new operator: " NEW_ENR
fi

# For new operators, require cluster-lock file
if [[ "$ROLE" == "new" ]]; then
    if [ -z "$CLUSTER_LOCK_FILE" ]; then
        read -p "Enter path to your cluster-lock.json file: " CLUSTER_LOCK_FILE
    fi
    
    if [ ! -f "$CLUSTER_LOCK_FILE" ]; then
        echo "Error: Cluster lock file not found: $CLUSTER_LOCK_FILE" >&2
        exit 1
    fi
fi

echo ""
echo "============================================"
echo "Charon Replace-Operator Ceremony"
echo "============================================"
echo "Role: $ROLE"
echo "Old operator ENR: $OLD_ENR"
echo "New operator ENR: $NEW_ENR"
if [[ "$ROLE" == "new" ]]; then
    echo "Cluster lock file: $CLUSTER_LOCK_FILE"
fi
echo "Output directory: $OUTPUT_DIR"
echo "Backup file: $BACKUP_FILE"
if [[ "$ROLE" == "continuing" ]]; then
    echo "ASDB directory: $ASDB_DIR"
fi
echo "============================================"
echo ""

# Check prerequisites
if [ ! -d .charon ]; then
    echo "Error: .charon directory not found" >&2
    echo "Please ensure you are running this script from the repository root" >&2
    exit 1
fi

# Check if output directory already exists
if [ -d "$OUTPUT_DIR" ]; then
    echo "Error: Output directory already exists: $OUTPUT_DIR" >&2
    echo "Please remove it before running the ceremony:" >&2
    echo "  rm -rf $OUTPUT_DIR" >&2
    echo "" >&2
    echo "If you are retrying after a failed ceremony, ensure the output" >&2
    echo "directory from the previous attempt is cleaned up." >&2
    exit 1
fi

# Check if zip command is available
if ! command -v zip &> /dev/null; then
    echo "Error: 'zip' command not found" >&2
    echo "Please install zip to create backups" >&2
    exit 1
fi

# Step 1: Create backup
echo "Step 1: Creating backup of .charon directory"
echo ""
read -p "Press Enter to create backup at $BACKUP_FILE (or Ctrl+C to abort)..."

if ! zip -r "$BACKUP_FILE" .charon > /dev/null; then
    echo "Error: Failed to create backup" >&2
    exit 1
fi

echo "✓ Backup created: $BACKUP_FILE"
echo ""

# Step 2: For continuing operators, prompt to export ASDB
if [[ "$ROLE" == "continuing" ]]; then
    echo "Step 2: Export anti-slashing database"
    echo ""
    echo "Before proceeding with the ceremony, you must export your"
    echo "anti-slashing database. Run the following command:"
    echo ""
    echo "  ./scripts/edit/lodestar/export_asdb.sh"
    echo ""
    read -p "Have you successfully exported the ASDB? (yes/no): " asdb_exported
    
    if [[ "$asdb_exported" != "yes" ]]; then
        echo "Please export the ASDB before continuing" >&2
        exit 1
    fi
    
    echo "✓ ASDB export confirmed"
    echo ""
fi

# Step 3: Execute ceremony
echo "Step 3: Execute replace-operator ceremony"
echo ""
echo "This will run the Charon ceremony with all participating operators."
echo "Ensure all operators are ready to execute this simultaneously."
echo ""
read -p "Press Enter to start the ceremony (or Ctrl+C to abort)..."


echo "Running ceremony..."
echo ""

# Execute the ceremony using docker compose run with appropriate volume mounts
# Using bash array for volumes to handle paths with spaces safely
VOLUMES=(
    -v "$(pwd)/.charon:/opt/charon/.charon"
    -v "$(pwd)/output:/opt/charon/output"
)

if [[ "$ROLE" == "new" ]]; then
    # For new operators, mount the cluster-lock file
    if [[ "$CLUSTER_LOCK_FILE" == /* ]]; then
        CLUSTER_LOCK_HOST_PATH="$CLUSTER_LOCK_FILE"
    else
        CLUSTER_LOCK_HOST_PATH="$(pwd)/$CLUSTER_LOCK_FILE"
    fi
    VOLUMES+=(-v "$CLUSTER_LOCK_HOST_PATH:/opt/charon/cluster-lock.json")
fi

if ! docker compose run --rm "${VOLUMES[@]}" charon alpha edit replace-operator \
    --old-operator-enr="$OLD_ENR" \
    --new-operator-enr="$NEW_ENR" \
    --output-dir=/opt/charon/output \
    $(if [[ "$ROLE" == "new" ]]; then echo "--lock-file=/opt/charon/cluster-lock.json --private-key-file=/opt/charon/charon-enr-private-key"; fi); then
    echo "" >&2
    echo "Error: Ceremony failed" >&2
    echo "" >&2
    echo "To rollback, restore your backup:" >&2
    echo "  rm -rf .charon && unzip $BACKUP_FILE" >&2
    exit 1
fi

echo ""
echo "✓ Ceremony completed successfully"
echo ""

# Step 4: For continuing operators, update ASDB
if [[ "$ROLE" == "continuing" ]]; then
    echo "Step 4: Update anti-slashing database"
    echo ""
    echo "Translating validator keys in the exported ASDB..."
    
    ASDB_FILE="$ASDB_DIR/slashing-protection.json"
    SOURCE_LOCK=".charon/cluster-lock.json"
    TARGET_LOCK="$OUTPUT_DIR/cluster-lock.json"
    
    if ! ./scripts/edit/lib/update-anti-slashing-db.sh "$ASDB_FILE" "$SOURCE_LOCK" "$TARGET_LOCK"; then
        echo "" >&2
        echo "Error: Failed to update ASDB" >&2
        echo "" >&2
        echo "To rollback:" >&2
        echo "  rm -rf .charon && unzip $BACKUP_FILE" >&2
        echo "  rm -rf $OUTPUT_DIR" >&2
        exit 1
    fi
    
    echo ""
    echo "✓ ASDB updated successfully"
    echo ""
fi

# Step 5: Display final instructions
echo "=========================================="
echo "Ceremony Completed Successfully!"
echo "=========================================="
echo ""

read -p "Press Enter to view the final steps..."

echo ""
echo "Next steps to activate the new cluster configuration:"
echo ""
echo "1. Stop services:"
echo "   docker compose stop charon vc-lodestar"
echo ""
echo "2. Activate new configuration:"
echo "   mv .charon .charon-old && mv $OUTPUT_DIR .charon"
echo ""

if [[ "$ROLE" == "continuing" ]]; then
    echo "3. Import updated anti-slashing database:"
    echo "   ./scripts/edit/lodestar/import_asdb.sh --input-file $ASDB_DIR/slashing-protection.json"
    echo ""
    echo "4. Coordinate with other operators:"
fi

if [[ "$ROLE" == "new" ]]; then
    echo "3. Coordinate with other operators:"
fi

echo "   Confirm in your meeting that all operators have completed the above steps"
echo ""

if [[ "$ROLE" == "continuing" ]]; then
    echo "5. Wait two epochs (approximately 13 minutes)"
    echo ""
    echo "6. Restart services together:"
else
    echo "4. Wait two epochs (approximately 13 minutes)"
    echo ""
    echo "5. Restart services together:"
fi

echo "   docker compose up -d charon vc-lodestar"
echo ""
echo "=========================================="
echo ""
echo "If anything goes wrong, rollback with:"
echo "  rm -rf .charon"
echo "  unzip $BACKUP_FILE"
echo "=========================================="
