#!/usr/bin/env bash

# Recreate-Private-Keys Script - See README.md for documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
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
Usage: ./scripts/edit/recreate-private-keys/recreate-private-keys.sh [OPTIONS]

Recreates validator private key shares for the cluster. This is a CEREMONY
that ALL operators must run simultaneously.

Use cases:
  - Security concerns: If private key shares may have been compromised
  - Key rotation: As part of regular security practices
  - Recovery: After a security incident to refresh key material

NOTE: This operation maintains the same validator public keys. Only the
underlying private key shares held by operators are refreshed.

Options:
  --dry-run        Show what would be done without executing
  -h, --help       Show this help message

Example:
  ./scripts/edit/recreate-private-keys/recreate-private-keys.sh

Prerequisites:
  - .env file with NETWORK and VC variables set
  - .charon directory with cluster-lock.json and validator_keys
  - Docker and docker compose installed and running
  - All operators must participate in the ceremony
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Recreate Private Keys Workflow                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 0: Check prerequisites
log_step "Step 0: Checking prerequisites..."

if [ ! -f .env ]; then
    log_error ".env file not found. Please create one with NETWORK and VC variables."
    exit 1
fi

# Preserve COMPOSE_FILE and COMPOSE_PROJECT_NAME if already set (e.g., by test scripts)
SAVED_COMPOSE_FILE="${COMPOSE_FILE:-}"
SAVED_COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"

source .env

# Restore COMPOSE_FILE and COMPOSE_PROJECT_NAME if they were set before sourcing .env
if [ -n "$SAVED_COMPOSE_FILE" ]; then
    export COMPOSE_FILE="$SAVED_COMPOSE_FILE"
fi
if [ -n "$SAVED_COMPOSE_PROJECT_NAME" ]; then
    export COMPOSE_PROJECT_NAME="$SAVED_COMPOSE_PROJECT_NAME"
fi

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

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY-RUN MODE: No changes will be made"
fi

echo ""

# Step 1: Export anti-slashing database
log_step "Step 1: Exporting anti-slashing database..."

# VC container must be stopped before export (Lodestar locks the database while running)
if [ "$DRY_RUN" = false ]; then
    if docker compose ps "$VC" 2>/dev/null | grep -q Up; then
        log_info "Stopping VC container ($VC) for ASDB export..."
        docker compose stop "$VC"
    fi
else
    log_warn "Would stop $VC container if running"
fi

mkdir -p "$ASDB_EXPORT_DIR"

VC="$VC" run_cmd "$SCRIPT_DIR/../vc/export_asdb.sh" \
    --output-file "$ASDB_EXPORT_DIR/slashing-protection.json"

log_info "Anti-slashing database exported to $ASDB_EXPORT_DIR/slashing-protection.json"

echo ""

# Step 2: Run ceremony
log_step "Step 2: Running recreate-private-keys ceremony..."

echo ""
log_warn "╔════════════════════════════════════════════════════════════════╗"
log_warn "║  IMPORTANT: ALL operators must run this ceremony simultaneously ║"
log_warn "╚════════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$OUTPUT_DIR"

log_info "Running: charon alpha edit recreate-private-keys"
log_info "  Output directory: $OUTPUT_DIR"
log_info ""
log_info "The ceremony will coordinate with other operators via P2P relay."
log_info "Please wait for all operators to connect..."
echo ""

if [ "$DRY_RUN" = false ]; then
    # Use -i for stdin (needed for ceremony coordination), skip -t if no TTY available
    DOCKER_FLAGS="-i"
    if [ -t 0 ]; then
        DOCKER_FLAGS="-it"
    fi
    
    docker run --rm $DOCKER_FLAGS \
        -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
        -v "$REPO_ROOT/$OUTPUT_DIR:/opt/charon/output" \
        "obolnetwork/charon:${CHARON_VERSION:-v1.9.0-rc3}" \
        alpha edit recreate-private-keys \
        --output-dir=/opt/charon/output

    # Verify ceremony output
    if [ -f "$OUTPUT_DIR/cluster-lock.json" ]; then
        log_info "Ceremony completed successfully!"
        log_info "New cluster-lock.json generated in $OUTPUT_DIR/"
    else
        log_error "Ceremony may have failed - no cluster-lock.json in $OUTPUT_DIR/"
        exit 1
    fi
else
    echo "  [DRY-RUN] docker run --rm -it ... charon alpha edit recreate-private-keys --output-dir=output"
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
log_info "New keys installed to .charon/"

echo ""

# Step 6: Import updated ASDB
log_step "Step 6: Importing updated anti-slashing database..."

VC="$VC" run_cmd "$SCRIPT_DIR/../vc/import_asdb.sh" \
    --input-file "$ASDB_EXPORT_DIR/slashing-protection.json"

log_info "Anti-slashing database imported"

echo ""

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Recreate Private Keys Workflow COMPLETED                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Old .charon backed up to: $BACKUP_DIR/.charon-backup.$TIMESTAMP"
log_info "  - New keys installed in: .charon/"
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
log_info "  2. Verify all nodes connected and healthy"
log_info "  3. Verify cluster is producing attestations"
log_info "  4. Check no signature verification errors in logs"
echo ""
log_warn "Keep the backup until you've verified normal operation for several epochs."
echo ""
