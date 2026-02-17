#!/usr/bin/env bash

# Add-Operators Script for NEW Operators
#
# This script helps new operators join an existing cluster during the
# add-operators ceremony.
#
# Reference: https://docs.obol.org/next/advanced-and-troubleshooting/advanced/add-operators
#
# IMPORTANT: This is a CEREMONY - ALL operators (existing AND new) must run
# their respective scripts simultaneously.
#
# Two-step workflow:
# 1. Generate your ENR and share it with existing operators
# 2. Run the ceremony with the cluster-lock received from existing operators
#
# Prerequisites:
# - .env file with NETWORK and VC variables set
# - For --generate-enr: Docker installed
# - For ceremony: .charon/charon-enr-private-key must exist
# - For ceremony: Cluster-lock.json received from existing operators
#
# Usage:
#   ./scripts/edit/add-operators/new-operator.sh [OPTIONS]
#
# Options:
#   --new-operator-enrs <enrs>  Comma-separated ENRs of ALL new operators (required for ceremony)
#   --cluster-lock <path>       Path to existing cluster-lock.json (required for ceremony)
#   --generate-enr              Generate a new ENR private key if not present
#   --dry-run                   Show what would be done without executing
#   -h, --help                  Show this help message
#
# Examples:
#   # Step 1: Generate ENR and share with existing operators
#   ./scripts/edit/add-operators/new-operator.sh --generate-enr
#
#   # Step 2: Run ceremony with all new operator ENRs
#   ./scripts/edit/add-operators/new-operator.sh \
#       --new-operator-enrs "enr:-...,enr:-..." \
#       --cluster-lock ./received-cluster-lock.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
NEW_OPERATOR_ENRS=""
CLUSTER_LOCK_PATH=""
GENERATE_ENR=false
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
Usage: ./scripts/edit/add-operators/new-operator.sh [OPTIONS]

Helps new operators join an existing cluster during the add-operators ceremony.
This is a CEREMONY that ALL operators (existing AND new) must run simultaneously.

Options:
  --new-operator-enrs <enrs>  Comma-separated ENRs of ALL new operators (required for ceremony)
  --cluster-lock <path>       Path to existing cluster-lock.json (required for ceremony)
  --generate-enr              Generate a new ENR private key if not present
  --dry-run                   Show what would be done without executing
  -h, --help                  Show this help message

Examples:
  # Step 1: Generate ENR and share with existing operators
  ./scripts/edit/add-operators/new-operator.sh --generate-enr

  # Step 2: Run ceremony with cluster-lock and all new operator ENRs
  ./scripts/edit/add-operators/new-operator.sh \
      --new-operator-enrs "enr:-...,enr:-..." \
      --cluster-lock ./received-cluster-lock.json

Prerequisites:
  - .env file with NETWORK and VC variables set
  - For --generate-enr: Docker installed
  - For ceremony: .charon/charon-enr-private-key must exist
  - For ceremony: Cluster-lock.json received from existing operators
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
        --cluster-lock)
            CLUSTER_LOCK_PATH="$2"
            shift 2
            ;;
        --generate-enr)
            GENERATE_ENR=true
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

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Add-Operators Workflow - NEW OPERATOR                      ║"
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

# Handle ENR generation mode
if [ "$GENERATE_ENR" = true ]; then
    log_step "Step 1: Generating ENR private key..."

    if [ -f .charon/charon-enr-private-key ]; then
        log_warn "ENR private key already exists at .charon/charon-enr-private-key"
        log_warn "Skipping generation to avoid overwriting existing key."
        log_info "If you want to generate a new key, remove the existing file first."
    else
        mkdir -p .charon

        if [ "$DRY_RUN" = false ]; then
            docker run --rm \
                -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
                "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}" \
                create enr
        else
            echo "  [DRY-RUN] docker run --rm ... charon create enr"
        fi

        log_info "ENR private key generated"
    fi

    if [ -f .charon/charon-enr-private-key ]; then
        echo ""
        log_warn "╔════════════════════════════════════════════════════════════════╗"
        log_warn "║  SHARE YOUR ENR WITH THE EXISTING OPERATORS                    ║"
        log_warn "╚════════════════════════════════════════════════════════════════╝"
        echo ""

        # Extract and display the ENR
        if [ "$DRY_RUN" = false ]; then
            ENR=$(docker run --rm \
                -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
                "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}" \
                enr 2>/dev/null || echo "")

            if [ -n "$ENR" ]; then
                log_info "Your ENR:"
                echo ""
                echo "$ENR"
                echo ""
            fi
        fi

        log_info "Send this ENR to the existing operators."
        log_info "They will use it with: --new-operator-enrs \"<your-enr>\""
        log_info ""
        log_info "You will also need the existing cluster-lock.json from them."
        log_info ""
        log_info "After receiving it, run the ceremony with:"
        log_info "  ./scripts/edit/add-operators/new-operator.sh \\"
        log_info "      --new-operator-enrs \"<all-new-enrs>\" \\"
        log_info "      --cluster-lock <path-to-cluster-lock.json>"
    fi

    exit 0
fi

# Ceremony mode: validate required arguments
if [ -z "$NEW_OPERATOR_ENRS" ]; then
    log_error "Missing required argument: --new-operator-enrs"
    echo "Use --help for usage information"
    exit 1
fi

if [ -z "$CLUSTER_LOCK_PATH" ]; then
    log_error "Missing required argument: --cluster-lock"
    echo "Use --help for usage information"
    exit 1
fi

# Step 1: Check ceremony prerequisites
log_step "Step 1: Checking ceremony prerequisites..."

if [ "$DRY_RUN" = false ]; then
    if [ ! -d .charon ]; then
        log_error ".charon directory not found"
        log_info "First generate your ENR with: ./scripts/edit/add-operators/new-operator.sh --generate-enr"
        exit 1
    fi

    if [ ! -f .charon/charon-enr-private-key ]; then
        log_error ".charon/charon-enr-private-key not found"
        log_info "First generate your ENR with: ./scripts/edit/add-operators/new-operator.sh --generate-enr"
        exit 1
    fi

    if [ ! -f "$CLUSTER_LOCK_PATH" ]; then
        log_error "Cluster-lock file not found: $CLUSTER_LOCK_PATH"
        exit 1
    fi

    # Validate cluster-lock is valid JSON
    if ! jq empty "$CLUSTER_LOCK_PATH" 2>/dev/null; then
        log_error "Cluster-lock file is not valid JSON: $CLUSTER_LOCK_PATH"
        exit 1
    fi
else
    if [ ! -d .charon ]; then
        log_warn "Would check for .charon directory (not found)"
    fi
    if [ ! -f .charon/charon-enr-private-key ]; then
        log_warn "Would check for .charon/charon-enr-private-key (not found)"
    fi
fi

log_info "Using cluster-lock: $CLUSTER_LOCK_PATH"
log_info "New operator ENRs: ${NEW_OPERATOR_ENRS:0:80}..."

# Show cluster info
if [ "$DRY_RUN" = false ] && [ -f "$CLUSTER_LOCK_PATH" ]; then
    NUM_VALIDATORS=$(jq '.distributed_validators | length' "$CLUSTER_LOCK_PATH" 2>/dev/null || echo "?")
    NUM_OPERATORS=$(jq '.operators | length' "$CLUSTER_LOCK_PATH" 2>/dev/null || echo "?")
    log_info "Cluster info: $NUM_VALIDATORS validator(s), $NUM_OPERATORS operator(s)"
fi

log_info "Prerequisites OK"

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
        -v "$REPO_ROOT/$CLUSTER_LOCK_PATH:/opt/charon/cluster-lock.json:ro" \
        "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}" \
        alpha edit add-operators \
        --new-operator-enrs="$NEW_OPERATOR_ENRS" \
        --output-dir=/opt/charon/output \
        --lock-file=/opt/charon/cluster-lock.json \
        --private-key-file=/opt/charon/.charon/charon-enr-private-key

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
    echo "  [DRY-RUN] docker run --rm -it ... charon alpha edit add-operators --new-operator-enrs=... --output-dir=$OUTPUT_DIR --lock-file=... --private-key-file=..."
fi

echo ""

# Step 3: Install .charon from output
log_step "Step 3: Installing new cluster configuration..."

if [ -d .charon ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    run_cmd mv .charon "$BACKUP_DIR/.charon-backup.$TIMESTAMP"
    log_info "Old .charon backed up to $BACKUP_DIR/.charon-backup.$TIMESTAMP"
fi

run_cmd mv "$OUTPUT_DIR" .charon
log_info "New cluster configuration installed to .charon/"

echo ""

# Step 4: Start containers
log_step "Step 4: Starting containers..."

run_cmd docker compose up -d charon "$VC"

log_info "Containers started"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     New Operator Setup COMPLETED                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Cluster configuration installed in: .charon/"
log_info "  - Containers started: charon, $VC"
echo ""
log_info "Next steps:"
log_info "  1. Wait for charon to sync with peers: docker compose logs -f charon"
log_info "  2. Verify VC is running: docker compose logs -f $VC"
log_info "  3. Monitor validator duties once synced"
echo ""
log_warn "Note: As a new operator, you do NOT have any slashing protection history."
log_warn "Your VC will start fresh. Ensure all existing operators have completed"
log_warn "their add-operators workflow before validators resume duties."
echo ""
