#!/usr/bin/env bash

# Replace-Operator Script for REMAINING Operators - See README.md for documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
NEW_ENR=""
OPERATOR_INDEX=""
SKIP_EXPORT=false
DRY_RUN=false

# Output directories
ASDB_EXPORT_DIR="./asdb-export"
OUTPUT_DIR="./output"
BACKUP_DIR="./backups"

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
Usage: ./scripts/edit/replace-operator/remaining-operator.sh [OPTIONS]

Automates the complete replace-operator workflow for operators
who are staying in the cluster (continuing operators).

Options:
  --new-enr <enr>         ENR of the new operator (required)
  --operator-index <N>    Index of the operator being replaced (required)
  --skip-export           Skip ASDB export (if already exported)
  --dry-run               Show what would be done without executing
  -h, --help              Show this help message

Example:
  ./scripts/edit/replace-operator/remaining-operator.sh \
      --new-enr "enr:-..." \
      --operator-index 2

Prerequisites:
  - .env file with NETWORK and VC variables set
  - .charon directory with cluster-lock.json and charon-enr-private-key
  - Docker and docker compose installed and running
  - VC container running (for initial export)
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --new-enr)
            NEW_ENR="$2"
            shift 2
            ;;
        --operator-index)
            OPERATOR_INDEX="$2"
            shift 2
            ;;
        --skip-export)
            SKIP_EXPORT=true
            shift
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
if [ -z "$NEW_ENR" ]; then
    log_error "Missing required argument: --new-enr"
    echo "Use --help for usage information"
    exit 1
fi
if [ -z "$OPERATOR_INDEX" ]; then
    log_error "Missing required argument: --operator-index"
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
echo "║     Replace-Operator Workflow - REMAINING OPERATOR             ║"
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

if [ ! -f .charon/charon-enr-private-key ]; then
    log_error ".charon/charon-enr-private-key not found"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
fi

log_info "Prerequisites OK"
log_info "  Network: $NETWORK"
log_info "  Validator Client: $VC"

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY-RUN MODE: No changes will be made"
fi

echo ""

# Step 1: Export anti-slashing database
log_step "Step 1: Exporting anti-slashing database..."

if [ "$SKIP_EXPORT" = true ]; then
    log_warn "Skipping export (--skip-export specified)"
    if [ ! -f "$ASDB_EXPORT_DIR/slashing-protection.json" ]; then
        log_error "Cannot skip export: $ASDB_EXPORT_DIR/slashing-protection.json not found"
        exit 1
    fi
else
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
    
    VC="$VC" run_cmd "$SCRIPT_DIR/../vc/export_asdb.sh" \
        --output-file "$ASDB_EXPORT_DIR/slashing-protection.json"
    
    log_info "Anti-slashing database exported to $ASDB_EXPORT_DIR/slashing-protection.json"
fi

echo ""

# Step 2: Run replace-operator ceremony
log_step "Step 2: Running replace-operator ceremony..."

mkdir -p "$OUTPUT_DIR"

log_info "Running: charon edit replace-operator"
log_info "  Replacing operator index: $OPERATOR_INDEX"
log_info "  New ENR: ${NEW_ENR:0:50}..."

if [ "$DRY_RUN" = false ]; then
    docker run --rm \
        -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
        -v "$REPO_ROOT/$OUTPUT_DIR:/opt/charon/output" \
        "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}" \
        edit replace-operator \
        --lock-file=/opt/charon/.charon/cluster-lock.json \
        --output-dir=/opt/charon/output \
        --operator-index="$OPERATOR_INDEX" \
        --new-enr="$NEW_ENR"
else
    echo "  [DRY-RUN] docker run --rm ... charon edit replace-operator ..."
fi

log_info "New cluster-lock generated at $OUTPUT_DIR/cluster-lock.json"

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
log_step "Step 4: Stopping charon and VC containers..."

run_cmd docker compose stop "$VC" charon

log_info "Containers stopped"

echo ""

# Step 5: Backup and replace cluster-lock
log_step "Step 5: Backing up and replacing cluster-lock..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

run_cmd cp .charon/cluster-lock.json "$BACKUP_DIR/cluster-lock.json.$TIMESTAMP"
log_info "Old cluster-lock backed up to $BACKUP_DIR/cluster-lock.json.$TIMESTAMP"

# Remove existing file first (may be read-only from Charon)
rm -f .charon/cluster-lock.json
run_cmd cp "$OUTPUT_DIR/cluster-lock.json" .charon/cluster-lock.json
log_info "New cluster-lock installed"

echo ""

# Step 6: Import updated ASDB
log_step "Step 6: Importing updated anti-slashing database..."

VC="$VC" run_cmd "$SCRIPT_DIR/../vc/import_asdb.sh" \
    --input-file "$ASDB_EXPORT_DIR/slashing-protection.json"

log_info "Anti-slashing database imported"

echo ""

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Replace-Operator Workflow COMPLETED                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Old cluster-lock backed up to: $BACKUP_DIR/cluster-lock.json.$TIMESTAMP"
log_info "  - New cluster-lock installed in: .charon/cluster-lock.json"
log_info "  - Anti-slashing database updated and imported"
echo ""
log_warn "╔════════════════════════════════════════════════════════════════╗"
log_warn "║  IMPORTANT: Wait at least 2 epochs (~13 min) before starting  ║"
log_warn "║  containers to avoid slashing risk from duplicate attestations║"
log_warn "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "When ready, start containers with:"
echo "  docker compose up -d charon $VC"
echo ""
log_info "After starting, verify:"
log_info "  1. Check charon logs: docker compose logs -f charon"
log_info "  2. Verify VC is running: docker compose logs -f $VC"
log_info "  3. Share the new cluster-lock.json with the NEW operator"
echo ""
log_warn "Keep the backup until you've verified normal operation for several epochs."
echo ""
