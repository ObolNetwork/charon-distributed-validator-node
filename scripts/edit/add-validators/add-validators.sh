#!/usr/bin/env bash

# Add-Validators Script - See README.md for documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
NUM_VALIDATORS=""
WITHDRAWAL_ADDRESSES=""
FEE_RECIPIENT_ADDRESSES=""
UNVERIFIED=false
DRY_RUN=false

# Output directories
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
Usage: ./scripts/edit/add-validators/add-validators.sh [OPTIONS]

Adds new validators to an existing distributed validator cluster.

Options:
  --num-validators <N>             Number of validators to add (required)
  --withdrawal-addresses <addr>    Withdrawal address(es), comma-separated (required)
  --fee-recipient-addresses <addr> Fee recipient address(es), comma-separated (required)
  --unverified                     Skip key verification (when keys not accessible)
  --dry-run                        Show what would be done without executing
  -h, --help                       Show this help message

See README.md for detailed documentation.
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --num-validators)
            NUM_VALIDATORS="$2"
            shift 2
            ;;
        --withdrawal-addresses)
            WITHDRAWAL_ADDRESSES="$2"
            shift 2
            ;;
        --fee-recipient-addresses)
            FEE_RECIPIENT_ADDRESSES="$2"
            shift 2
            ;;
        --unverified)
            UNVERIFIED=true
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
if [ -z "$NUM_VALIDATORS" ]; then
    log_error "Missing required argument: --num-validators"
    echo "Use --help for usage information"
    exit 1
fi

if [ -z "$WITHDRAWAL_ADDRESSES" ]; then
    log_error "Missing required argument: --withdrawal-addresses"
    echo "Use --help for usage information"
    exit 1
fi

if [ -z "$FEE_RECIPIENT_ADDRESSES" ]; then
    log_error "Missing required argument: --fee-recipient-addresses"
    echo "Use --help for usage information"
    exit 1
fi

# Validate num-validators is a positive integer
if ! [[ "$NUM_VALIDATORS" =~ ^[1-9][0-9]*$ ]]; then
    log_error "Invalid --num-validators: must be a positive integer"
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
echo "║     Add Validators Workflow                                    ║"
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

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
fi

# Check if containers are currently running
CHARON_WAS_RUNNING=false
VC_WAS_RUNNING=false
if docker compose ps charon 2>/dev/null | grep -q Up; then
    CHARON_WAS_RUNNING=true
fi
if docker compose ps "$VC" 2>/dev/null | grep -q Up; then
    VC_WAS_RUNNING=true
fi

log_info "Prerequisites OK"
log_info "  Network: $NETWORK"
log_info "  Validator Client: $VC"
log_info "  Validators to add: $NUM_VALIDATORS"

if [ -n "$WITHDRAWAL_ADDRESSES" ]; then
    log_info "  Withdrawal addresses: $WITHDRAWAL_ADDRESSES"
fi
if [ -n "$FEE_RECIPIENT_ADDRESSES" ]; then
    log_info "  Fee recipient addresses: $FEE_RECIPIENT_ADDRESSES"
fi
if [ "$UNVERIFIED" = true ]; then
    log_warn "  Mode: UNVERIFIED (key verification skipped)"
fi

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY-RUN MODE: No changes will be made"
fi

# Check if output directory already exists
if [ -d "$OUTPUT_DIR" ]; then
    log_error "Output directory '$OUTPUT_DIR' already exists."
    log_error "Please remove it first: rm -rf $OUTPUT_DIR"
    exit 1
fi

# Show current cluster info
if [ -f .charon/cluster-lock.json ]; then
    CURRENT_VALIDATORS=$(jq '.distributed_validators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
    CURRENT_OPERATORS=$(jq '.operators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
    log_info "  Current cluster: $CURRENT_VALIDATORS validator(s), $CURRENT_OPERATORS operator(s)"
fi

echo ""

# Step 1: Run ceremony
log_step "Step 1: Running add-validators ceremony..."

echo ""
log_warn "╔════════════════════════════════════════════════════════════════╗"
log_warn "║  IMPORTANT: ALL operators must run this ceremony simultaneously ║"
log_warn "╚════════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$OUTPUT_DIR"

log_info "Running: charon alpha edit add-validators"
log_info "  Number of validators: $NUM_VALIDATORS"
log_info "  Output directory: $OUTPUT_DIR"
log_info ""
log_info "The ceremony will coordinate with other operators via P2P relay."
log_info "Please wait for all operators to connect..."
echo ""

# Build Docker command arguments
DOCKER_ARGS=(
    run --rm -it
    -v "$REPO_ROOT/.charon:/opt/charon/.charon"
    -v "$REPO_ROOT/$OUTPUT_DIR:/opt/charon/output"
    "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}"
    alpha edit add-validators
    --num-validators="$NUM_VALIDATORS"
    --output-dir=/opt/charon/output
)

if [ -n "$WITHDRAWAL_ADDRESSES" ]; then
    DOCKER_ARGS+=(--withdrawal-addresses="$WITHDRAWAL_ADDRESSES")
fi

if [ -n "$FEE_RECIPIENT_ADDRESSES" ]; then
    DOCKER_ARGS+=(--fee-recipient-addresses="$FEE_RECIPIENT_ADDRESSES")
fi

if [ "$UNVERIFIED" = true ]; then
    DOCKER_ARGS+=(--unverified)
fi

if [ "$DRY_RUN" = false ]; then
    docker "${DOCKER_ARGS[@]}"

    # Verify ceremony output
    if [ -f "$OUTPUT_DIR/cluster-lock.json" ]; then
        log_info "Ceremony completed successfully!"
        NEW_VALIDATORS=$(jq '.distributed_validators | length' "$OUTPUT_DIR/cluster-lock.json" 2>/dev/null || echo "?")
        log_info "New cluster-lock.json generated with $NEW_VALIDATORS validator(s)"
    else
        log_error "Ceremony may have failed - no cluster-lock.json in $OUTPUT_DIR/"
        exit 1
    fi
else
    echo "  [DRY-RUN] docker run --rm -it ... charon alpha edit add-validators --num-validators=$NUM_VALIDATORS --output-dir=$OUTPUT_DIR"
fi

echo ""

# Step 2: Stop containers (if they were running)
log_step "Step 2: Stopping containers..."

if [ "$CHARON_WAS_RUNNING" = true ] || [ "$VC_WAS_RUNNING" = true ]; then
    run_cmd docker compose stop "$VC" charon
    log_info "Containers stopped"
else
    log_info "Containers were not running, skipping stop"
fi

echo ""

# Step 3: Backup and replace .charon
log_step "Step 3: Backing up and replacing .charon directory..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

run_cmd mv .charon "$BACKUP_DIR/.charon-backup.$TIMESTAMP"
log_info "Current .charon backed up to $BACKUP_DIR/.charon-backup.$TIMESTAMP"

run_cmd mv "$OUTPUT_DIR" .charon
log_info "New cluster configuration installed to .charon/"

echo ""

# Step 4: Restart containers (if they were running before)
log_step "Step 4: Restarting containers..."

if [ "$CHARON_WAS_RUNNING" = true ] || [ "$VC_WAS_RUNNING" = true ]; then
    if [ "$UNVERIFIED" = true ]; then
        log_warn "Starting charon with CHARON_NO_VERIFY=true (required for --unverified mode)"
    fi
    run_cmd docker compose up -d charon "$VC"
    log_info "Containers restarted"
else
    log_info "Containers were not running before, skipping restart"
    log_info "Start manually with: docker compose up -d charon $VC"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Add Validators Workflow COMPLETED                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Old .charon backed up to: $BACKUP_DIR/.charon-backup.$TIMESTAMP"
log_info "  - New cluster configuration installed in: .charon/"
log_info "  - $NUM_VALIDATORS new validator(s) added"
if [ "$CHARON_WAS_RUNNING" = true ] || [ "$VC_WAS_RUNNING" = true ]; then
    log_info "  - Containers restarted: charon, $VC"
else
    log_info "  - Containers not restarted (were not running)"
fi

if [ "$UNVERIFIED" = true ]; then
    echo ""
    log_warn "IMPORTANT: You used --unverified mode."
    log_warn "Ensure CHARON_NO_VERIFY=true is set in your .env file for future restarts."
fi

echo ""
log_info "Next steps:"
log_info "  1. Check charon logs: docker compose logs -f charon"
log_info "  2. Wait for threshold operators to complete their upgrades"
log_info "  3. Verify new validators appear in cluster"
log_info "  4. Generate deposit data for new validators (in .charon/deposit-data.json)"
log_info "  5. Activate new validators on the beacon chain"
echo ""
log_warn "Keep the backup until you've verified normal operation for several epochs."
echo ""

