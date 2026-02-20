#!/usr/bin/env bash

# Remove-Operators Script for REMOVED Operators - See README.md for documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
OPERATOR_ENRS_TO_REMOVE=""
PARTICIPATING_OPERATOR_ENRS=""
NEW_THRESHOLD=""
DRY_RUN=false

# Output directories
OUTPUT_DIR="./output"

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
Usage: ./scripts/edit/remove-operators/removed-operator.sh [OPTIONS]

Helps removed operators participate in the remove-operators ceremony.
This is only required when the removal exceeds the cluster's fault tolerance.

If the removal is within fault tolerance, removed operators do NOT need to
run this script - simply stop your node after the remaining operators complete
the ceremony.

Options:
  --operator-enrs-to-remove <enrs>      Comma-separated ENRs of operators to remove (required)
  --participating-operator-enrs <enrs>  Comma-separated ENRs of ALL participating operators (required)
  --new-threshold <N>                   Override default threshold (defaults to ceil(n * 2/3))
  --dry-run                             Show what would be done without executing
  -h, --help                            Show this help message

Example:
  ./scripts/edit/remove-operators/removed-operator.sh \
      --operator-enrs-to-remove "enr:-..." \
      --participating-operator-enrs "enr:-...,enr:-...,enr:-..."

Prerequisites:
  - .env file with NETWORK and VC variables set
  - .charon directory with cluster-lock.json, charon-enr-private-key, and validator_keys
  - Docker and docker compose installed and running
  - Your ENR must be listed in --participating-operator-enrs
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --operator-enrs-to-remove)
            OPERATOR_ENRS_TO_REMOVE="$2"
            shift 2
            ;;
        --participating-operator-enrs)
            PARTICIPATING_OPERATOR_ENRS="$2"
            shift 2
            ;;
        --new-threshold)
            NEW_THRESHOLD="$2"
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
if [ -z "$OPERATOR_ENRS_TO_REMOVE" ]; then
    log_error "Missing required argument: --operator-enrs-to-remove"
    echo "Use --help for usage information"
    exit 1
fi

if [ -z "$PARTICIPATING_OPERATOR_ENRS" ]; then
    log_error "Missing required argument: --participating-operator-enrs"
    echo "Use --help for usage information"
    exit 1
fi

# Validate new-threshold is a positive integer if provided
if [ -n "$NEW_THRESHOLD" ] && ! [[ "$NEW_THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
    log_error "Invalid --new-threshold: must be a positive integer"
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
echo "║     Remove-Operators Workflow - REMOVED OPERATOR               ║"
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

if [ ! -f .charon/charon-enr-private-key ]; then
    log_error ".charon/charon-enr-private-key not found"
    exit 1
fi

if [ ! -d .charon/validator_keys ]; then
    log_error ".charon/validator_keys directory not found"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
fi

log_info "Prerequisites OK"
log_info "  Network: $NETWORK"
log_info "  Validator Client: $VC"
log_info "  Operators to remove: ${OPERATOR_ENRS_TO_REMOVE:0:80}..."
log_info "  Participating operators: ${PARTICIPATING_OPERATOR_ENRS:0:80}..."

if [ -n "$NEW_THRESHOLD" ]; then
    log_info "  New threshold: $NEW_THRESHOLD"
fi

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

# Step 1: Run ceremony
log_step "Step 1: Running remove-operators ceremony..."

echo ""
log_warn "╔════════════════════════════════════════════════════════════════╗"
log_warn "║  IMPORTANT: ALL participating operators must run simultaneously║"
log_warn "╚════════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$OUTPUT_DIR"

log_info "Running: charon alpha edit remove-operators (as removed operator)"
log_info "  Operators to remove: ${OPERATOR_ENRS_TO_REMOVE:0:80}..."
log_info "  Output directory: $OUTPUT_DIR"
log_info ""
log_info "The ceremony will coordinate with other operators via P2P relay."
log_info "Please wait for all participants to connect..."
echo ""

if [ "$DRY_RUN" = false ]; then
    # Use -i for stdin (needed for ceremony coordination), skip -t if no TTY available
    DOCKER_FLAGS="-i"
    if [ -t 0 ]; then
        DOCKER_FLAGS="-it"
    fi
    
    # Build Docker command arguments
    DOCKER_ARGS=(
        run --rm $DOCKER_FLAGS
        -v "$REPO_ROOT/.charon:/opt/charon/.charon"
        -v "$REPO_ROOT/$OUTPUT_DIR:/opt/charon/output"
        "obolnetwork/charon:${CHARON_VERSION:-v1.9.0-rc3}"
        alpha edit remove-operators
        --operator-enrs-to-remove="$OPERATOR_ENRS_TO_REMOVE"
        --participating-operator-enrs="$PARTICIPATING_OPERATOR_ENRS"
        --private-key-file=/opt/charon/.charon/charon-enr-private-key
        --lock-file=/opt/charon/.charon/cluster-lock.json
        --validator-keys-dir=/opt/charon/.charon/validator_keys
        --output-dir=/opt/charon/output
    )

    if [ -n "$NEW_THRESHOLD" ]; then
        DOCKER_ARGS+=(--new-threshold="$NEW_THRESHOLD")
    fi

    docker "${DOCKER_ARGS[@]}"

    log_info "Ceremony completed successfully!"
else
    echo "  [DRY-RUN] docker run --rm -it ... charon alpha edit remove-operators --operator-enrs-to-remove=... --participating-operator-enrs=... --output-dir=$OUTPUT_DIR"
fi

echo ""

# Step 2: Stop containers
log_step "Step 2: Stopping containers..."

run_cmd docker compose stop "$VC" charon

log_info "Containers stopped"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Removed Operator Workflow COMPLETED                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Ceremony participation completed"
log_info "  - Containers stopped: charon, $VC"
echo ""
log_warn "You have been removed from the cluster."
log_warn "Your node no longer needs to run for this cluster."
echo ""
log_info "Next steps:"
log_info "  1. Confirm with remaining operators that the ceremony succeeded"
log_info "  2. Optionally clean up cluster data: rm -rf .charon data/"
log_info "  3. Optionally remove Docker resources: docker compose down -v"
echo ""
