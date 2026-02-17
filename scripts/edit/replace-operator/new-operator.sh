#!/usr/bin/env bash

# Replace-Operator Workflow Script for NEW Operator
#
# This script helps a new operator join an existing cluster after a
# replace-operator ceremony has been completed by the remaining operators.
#
# Prerequisites (before running this script):
# 1. Generate your ENR private key:
#    docker run --rm -v "$(pwd)/.charon:/opt/charon/.charon" obolnetwork/charon:latest create enr
#
# 2. Share your ENR (found in .charon/charon-enr-private-key.pub or printed by the command)
#    with the remaining operators so they can run the ceremony.
#
# 3. Receive the new cluster-lock.json from the remaining operators after
#    they complete the ceremony.
#
# The workflow:
# 1. Verify prerequisites (.charon folder, private key, cluster-lock)
# 2. Stop any running containers
# 3. Place the new cluster-lock.json (if not already in place)
# 4. Start charon and VC containers
#
# Usage:
#   ./scripts/edit/replace-operator/new-operator.sh [OPTIONS]
#
# Options:
#   --cluster-lock <path>     Path to the new cluster-lock.json file (optional if already in .charon)
#   --generate-enr            Generate a new ENR private key if not present
#   --dry-run                 Show what would be done without executing
#   -h, --help                Show this help message
#
# Examples:
#   # Generate ENR first (share the output with remaining operators)
#   ./scripts/edit/replace-operator/new-operator.sh --generate-enr
#
#   # After receiving cluster-lock, join the cluster
#   ./scripts/edit/replace-operator/new-operator.sh --cluster-lock ./received-cluster-lock.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
CLUSTER_LOCK_PATH=""
GENERATE_ENR=false
DRY_RUN=false

# Output directories
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
Usage: ./scripts/edit/replace-operator/new-operator.sh [OPTIONS]

Helps a new operator join an existing cluster after a replace-operator
ceremony has been completed by the remaining operators.

Options:
  --cluster-lock <path>   Path to the new cluster-lock.json file
  --generate-enr          Generate a new ENR private key if not present
  --dry-run               Show what would be done without executing
  -h, --help              Show this help message

Examples:
  # Step 1: Generate ENR and share with remaining operators
  ./scripts/edit/replace-operator/new-operator.sh --generate-enr

  # Step 2: After receiving cluster-lock, join the cluster
  ./scripts/edit/replace-operator/new-operator.sh --cluster-lock ./received-cluster-lock.json

Prerequisites:
  - .env file with NETWORK and VC variables set
  - For --generate-enr: Docker installed
  - For joining: .charon/charon-enr-private-key must exist
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
echo "║     Replace-Operator Workflow - NEW OPERATOR                   ║"
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

# Step 1: Handle ENR generation
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
        log_warn "║  SHARE YOUR ENR WITH THE REMAINING OPERATORS                   ║"
        log_warn "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Extract and display the ENR
        if [ -f .charon/charon-enr-private-key ]; then
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
        
        log_info "Send this ENR to the remaining operators."
        log_info "They will use it with: --new-enr \"<your-enr>\""
        log_info ""
        log_info "After they complete the ceremony, run this script again with:"
        log_info "  ./scripts/edit/replace-operator/new-operator.sh --cluster-lock <path-to-cluster-lock.json>"
    fi
    
    exit 0
fi

# Step 1: Check prerequisites
log_step "Step 1: Checking prerequisites..."

if [ "$DRY_RUN" = false ]; then
    if [ ! -d .charon ]; then
        log_error ".charon directory not found"
        log_info "First generate your ENR with: ./scripts/edit/replace-operator/new-operator.sh --generate-enr"
        exit 1
    fi

    if [ ! -f .charon/charon-enr-private-key ]; then
        log_error ".charon/charon-enr-private-key not found"
        log_info "First generate your ENR with: ./scripts/edit/replace-operator/new-operator.sh --generate-enr"
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

# Handle cluster-lock
if [ -n "$CLUSTER_LOCK_PATH" ]; then
    if [ "$DRY_RUN" = false ] && [ ! -f "$CLUSTER_LOCK_PATH" ]; then
        log_error "Cluster-lock file not found: $CLUSTER_LOCK_PATH"
        exit 1
    fi
    log_info "Using provided cluster-lock: $CLUSTER_LOCK_PATH"
elif [ -f .charon/cluster-lock.json ]; then
    log_info "Using existing cluster-lock: .charon/cluster-lock.json"
elif [ "$DRY_RUN" = true ]; then
    log_warn "Would need cluster-lock.json (not found)"
else
    log_error "No cluster-lock.json found"
    log_info "Provide the path to the new cluster-lock.json with:"
    log_info "  ./scripts/edit/replace-operator/new-operator.sh --cluster-lock <path>"
    exit 1
fi

log_info "Prerequisites OK"

echo ""

# Step 2: Stop any running containers
log_step "Step 2: Stopping any running containers..."

# Stop containers if running (ignore errors if not running)
run_cmd docker compose stop "$VC" charon 2>/dev/null || true

log_info "Containers stopped"

echo ""

# Step 3: Install cluster-lock if provided
if [ -n "$CLUSTER_LOCK_PATH" ]; then
    log_step "Step 3: Installing new cluster-lock..."
    
    if [ -f .charon/cluster-lock.json ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$BACKUP_DIR"
        run_cmd cp .charon/cluster-lock.json "$BACKUP_DIR/cluster-lock.json.$TIMESTAMP"
        log_info "Old cluster-lock backed up to $BACKUP_DIR/cluster-lock.json.$TIMESTAMP"
    fi
    
    run_cmd cp "$CLUSTER_LOCK_PATH" .charon/cluster-lock.json
    log_info "New cluster-lock installed"
else
    log_step "Step 3: Using existing cluster-lock..."
    log_info "cluster-lock.json already in place"
fi

echo ""

# Step 4: Verify cluster-lock matches our ENR
log_step "Step 4: Verifying cluster-lock configuration..."

if [ "$DRY_RUN" = false ] && [ -f .charon/cluster-lock.json ]; then
    # Get our ENR
    OUR_ENR=$(docker run --rm \
        -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
        "obolnetwork/charon:${CHARON_VERSION:-v1.8.2}" \
        enr 2>/dev/null || echo "")
    
    if [ -n "$OUR_ENR" ]; then
        # Check if our ENR is in the cluster-lock
        if grep -q "${OUR_ENR:0:50}" .charon/cluster-lock.json 2>/dev/null; then
            log_info "Verified: Your ENR is present in the cluster-lock"
        else
            log_warn "Your ENR may not be in this cluster-lock."
            log_warn "Make sure you received the correct cluster-lock from the remaining operators."
        fi
    fi
    
    # Show cluster info
    NUM_VALIDATORS=$(jq '.distributed_validators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
    NUM_OPERATORS=$(jq '.operators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
    log_info "Cluster info: $NUM_VALIDATORS validator(s), $NUM_OPERATORS operator(s)"
fi

echo ""

# Step 5: Start containers
log_step "Step 5: Starting containers..."

run_cmd docker compose up -d charon "$VC"

log_info "Containers started"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     New Operator Setup COMPLETED                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Summary:"
log_info "  - Cluster-lock installed in: .charon/cluster-lock.json"
log_info "  - Containers started: charon, $VC"
echo ""
log_info "Next steps:"
log_info "  1. Wait for charon to sync with peers: docker compose logs -f charon"
log_info "  2. Verify VC is running: docker compose logs -f $VC"
log_info "  3. Monitor validator duties once synced"
echo ""
log_warn "Note: As a new operator, you do NOT have any slashing protection history."
log_warn "Your VC will start fresh. Ensure all remaining operators have completed"
log_warn "their replace-operator workflow before validators resume duties."
echo ""
