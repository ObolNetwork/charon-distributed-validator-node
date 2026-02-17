#!/usr/bin/env bash

# Add-Operators Script for EXISTING Operators
#
# This script automates the add-operators ceremony for operators who are
# already in the cluster. It handles the full workflow including ASDB
# export/update/import around the ceremony.
#
# Reference: https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-operators
#
# IMPORTANT: This is a CEREMONY - ALL operators (existing AND new) must run
# their respective scripts simultaneously. The ceremony coordinates between
# all operators to generate new key shares for the expanded operator set.
#
# The workflow:
# 1. Export the current anti-slashing database
# 2. Run the add-operators ceremony (all operators simultaneously)
# 3. Update the exported ASDB with new pubkeys
# 4. Stop containers
# 5. Backup and replace .charon directory
# 6. Import the updated ASDB
# 7. Restart containers
#
# Prerequisites:
# - .env file with NETWORK and VC variables set
# - .charon directory with cluster-lock.json and validator_keys
# - Docker and docker compose installed and running
# - VC container running (for ASDB export)
# - All operators must participate in the ceremony
#
# Usage:
#   ./scripts/edit/add-operators/existing-operator.sh [OPTIONS]
#
# Options:
#   --new-operator-enrs <enrs>  Comma-separated ENRs of new operators (required)
#   --dry-run                   Show what would be done without executing
#   -h, --help                  Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

# Default values
NEW_OPERATOR_ENRS=""
DRY_RUN=false

# Output directories
OUTPUT_DIR="./output"
BACKUP_DIR="./backups"
ASDB_EXPORT_DIR="./asdb-export"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

usage() {
    cat << 'EOF'
Usage: ./scripts/edit/add-operators/existing-operator.sh [OPTIONS]

Automates the add-operators ceremony for operators already in the cluster.
This is a CEREMONY that ALL operators (existing AND new) must run simultaneously.

Options:
  --new-operator-enrs <enrs>  Comma-separated ENRs of new operators (required)
  --dry-run                   Show what would be done without executing
  -h, --help                  Show this help message

Example:
  # Add one new operator
  ./scripts/edit/add-operators/existing-operator.sh \
      --new-operator-enrs "enr:-..."

  # Add multiple new operators
  ./scripts/edit/add-operators/existing-operator.sh \
      --new-operator-enrs "enr:-...,enr:-..."

Prerequisites:
  - .env file with NETWORK and VC variables set
  - .charon directory with cluster-lock.json and validator_keys
  - Docker and docker compose installed and running
  - VC container running (for ASDB export)
  - All operators must participate in the ceremony
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --new-operator-enrs)
            NEW_OPERATOR_ENRS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$NEW_OPERATOR_ENRS" ]; then
    log_error "Missing required argument: --new-operator-enrs"
    echo "Use --help for usage information"
    exit 1
fi

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Add-Operators Workflow - EXISTING OPERATOR                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 0: Check prerequisites
log_step "Step 0: Checking prerequisites..."

if [ ! -f .env ]; then
    log_error ".env file not found. Please create one with NETWORK and VC variables."
    exit 1
fi

source .env

if [ -z "${NETWORK:-}" ]; then
    log_error "NETWORK variable not set in .env"
    exit 1
fi

if [ -z "${VC:-}" ]; then
    log_error "VC variable not set in .env (e.g., vc-lodestar, vc-teku, vc-prysm, vc-nimbus)"
    exit 1
fi

if [ ! -d .charon ]; then
    log_error ".charon directory not found"
    exit 1
fi

if [ ! -f .charon/cluster-lock.json ]; then
    log_error ".charon/cluster-lock.json not found"
    exit 1
fi

if [ ! -d .charon/validator_keys ]; then
    log_error ".charon/validator_keys directory not found"
    log_info "All operators must have their current validator private key shares."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
fi

log_info "Prerequisites OK"
log_info "  Network: $NETWORK"
log_info "  Validator Client: $VC"
log_info "  New operator ENRs: ${NEW_OPERATOR_ENRS:0:80}..."

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY-RUN MODE: No changes will be made"
fi

# Show current cluster info
if [ -f .charon/cluster-lock.json ]; then
    CURRENT_VALIDATORS=$(jq '.distributed_validators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
    CURRENT_OPERATORS=$(jq '.operators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
    log_info "  Current cluster: $CURRENT_VALIDATORS validator(s), $CURRENT_OPERATORS operator(s)"
fi

echo ""

# Step 1: Export anti-slashing database
log_step "Step 1: Exporting anti-slashing database..."

# Check VC container is running (skip check in dry-run mode)
if [ "$DRY_RUN" = false ]; then
    if ! docker compose ps "$VC" 2>/dev/null | grep -q Up; then
        log_error "VC container ($VC) is not running. Start it first:"
        log_error "  docker compose up -d $VC"
        exit 1
    fi
else
    log_warn "Would check that $VC container is running"
fi

mkdir -p "$ASDB_EXPORT_DIR"

run_cmd VC="$VC" "$SCRIPT_DIR/../vc/export_asdb.sh" \
    --output-file "$ASDB_EXPORT_DIR/slashing-protection.json"

log_info "Anti-slashing database exported to $ASDB_EXPORT_DIR/slashing-protection.json"

echo ""

# Step 2: Run ceremony
log_step "Step 2: Running add-operators ceremony..."

echo ""
log_warn "╔════════════════════════════════════════════════════════════════╗"
log_warn "║  IMPORTANT: ALL operators must run this ceremony simultaneously ║"
log_warn "╚════════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$OUTPUT_DIR"

log_info "Running: charon alpha edit add-operators"
log_info "  New operator ENRs: ${NEW_OPERATOR_ENRS:0:80}..."
log_info "  Output directory: $OUTPUT_DIR"
log_info ""
log_info "The ceremony will coordinate with other operators via P2P relay."
log_info "Please wait for all operators to connect..."
echo ""

if [ "$DRY_RUN" = false ]; then
    docker run --rm -it \
        -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
        -v "$REPO_ROOT/$OUTPUT_DIR:/opt/charon/output" \
        "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}" \
        alpha edit add-operators \
        --new-operator-enrs="$NEW_OPERATOR_ENRS" \
        --output-dir=/opt/charon/output

    # Verify ceremony output
    if [ -f "$OUTPUT_DIR/cluster-lock.json" ]; then
        log_info "Ceremony completed successfully!"
        NEW_VALIDATORS=$(jq '.distributed_validators | length' "$OUTPUT_DIR/cluster-lock.json" 2>/dev/null || echo "?")
        NEW_OPERATORS=$(jq '.operators | length' "$OUTPUT_DIR/cluster-lock.json" 2>/dev/null || echo "?")
        log_info "New cluster-lock.json generated with $NEW_VALIDATORS validator(s), $NEW_OPERATORS operator(s)"
    else
        log_error "Ceremony may have failed - no cluster-lock.json in $OUTPUT_DIR/"
        exit 1
    fi
else
    echo "  [DRY-RUN] docker run --rm -it ... charon alpha edit add-operators --new-operator-enrs=... --output-dir=$OUTPUT_DIR"
fi

echo ""

# Step 3: Update ASDB pubkeys
log_step "Step 3: Updating anti-slashing database pubkeys..."

run_cmd "$SCRIPT_DIR/../vc/update-anti-slashing-db.sh" \
    "$ASDB_EXPORT_DIR/slashing-protection.json" \
    ".charon/cluster-lock.json" \
    "$OUTPUT_DIR/cluster-lock.json"

log_info "Anti-slashing database pubkeys updated"

echo ""

# Step 4: Stop containers
log_step "Step 4: Stopping containers..."

run_cmd docker compose stop "$VC" charon

log_info "Containers stopped"

echo ""

# Step 5: Backup and replace .charon
log_step "Step 5: Backing up and replacing .charon directory..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

run_cmd mv .charon "$BACKUP_DIR/.charon-backup.$TIMESTAMP"
log_info "Current .charon backed up to $BACKUP_DIR/.charon-backup.$TIMESTAMP"

run_cmd mv "$OUTPUT_DIR" .charon
log_info "New cluster configuration installed to .charon/"

echo ""

# Step 6: Import updated ASDB
log_step "Step 6: Importing updated anti-slashing database..."

run_cmd VC="$VC" "$SCRIPT_DIR/../vc/import_asdb.sh" \
    --input-file "$ASDB_EXPORT_DIR/slashing-protection.json"

log_info "Anti-slashing database imported"

echo ""

# Step 7: Restart containers
log_step "Step 7: Restarting containers..."

run_cmd docker compose up -d charon "$VC"

log_info "Containers restarted"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Add-Operators Workflow COMPLETED                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Old .charon backed up to: $BACKUP_DIR/.charon-backup.$TIMESTAMP"
log_info "  - New cluster configuration installed in: .charon/"
log_info "  - Anti-slashing database updated and imported"
log_info "  - Containers restarted: charon, $VC"
echo ""
log_info "Next steps:"
log_info "  1. Check charon logs: docker compose logs -f charon"
log_info "  2. Verify all nodes connected and healthy"
log_info "  3. Verify cluster is producing attestations"
log_info "  4. Confirm new operators have joined successfully"
echo ""
log_warn "Keep the backup until you've verified normal operation for several epochs."
echo ""
log_info "Current limitations:"
log_info "  - The new configuration will not be reflected on the Obol Launchpad"
log_info "  - The cluster will have a new cluster hash (different observability ID)"
echo ""
