#!/usr/bin/env bash

# Replace-Operator Script for NEW Operator - See README.md for documentation
# The new operator participates in the ceremony together with remaining operators.
# Both run the same `charon alpha edit replace-operator` command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${WORK_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
cd "$REPO_ROOT"

# Default values
CLUSTER_LOCK_PATH=""
OLD_ENR=""
GENERATE_ENR=false
DRY_RUN=false

# Output directories
BACKUP_DIR="./backups"
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
Usage: ./scripts/edit/replace-operator/new-operator.sh [OPTIONS]

Helps a new operator join an existing cluster by participating in the
replace-operator ceremony together with the remaining operators.
Both remaining and new operators run the same ceremony command.

Options:
  --cluster-lock <path>   Path to the current cluster-lock.json (for ceremony)
  --old-enr <enr>         ENR of the operator being replaced (for ceremony)
  --generate-enr          Generate a new ENR private key if not present
  --dry-run               Show what would be done without executing
  -h, --help              Show this help message

Examples:
  # Step 1: Generate ENR and share with remaining operators
  ./scripts/edit/replace-operator/new-operator.sh --generate-enr

  # Step 2: Run ceremony (after receiving cluster-lock from remaining operators)
  ./scripts/edit/replace-operator/new-operator.sh \
      --cluster-lock ./received-cluster-lock.json \
      --old-enr "enr:-..."

Prerequisites:
  - .env file with NETWORK and VC variables set
  - For --generate-enr: Docker installed
  - For ceremony: .charon/charon-enr-private-key must exist
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
        --old-enr)
            OLD_ENR="$2"
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
                "obolnetwork/charon:${CHARON_VERSION:-v1.9.0-rc3}" \
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
                "obolnetwork/charon:${CHARON_VERSION:-v1.9.0-rc3}" \
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
        log_info "Ask them to share the current cluster-lock.json with you BEFORE the ceremony."
        log_info ""
        log_info "Then run the ceremony together with remaining operators using:"
        log_info "  ./scripts/edit/replace-operator/new-operator.sh --cluster-lock <path> --old-enr <enr>"
    fi
    
    exit 0
fi

# Ceremony mode: --cluster-lock + --old-enr
if [ -n "$CLUSTER_LOCK_PATH" ] && [ -n "$OLD_ENR" ]; then
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
        
        if [ ! -f "$CLUSTER_LOCK_PATH" ]; then
            log_error "Cluster-lock file not found: $CLUSTER_LOCK_PATH"
            exit 1
        fi
    fi
    
    log_info "Prerequisites OK"
    log_info "  Using cluster-lock: $CLUSTER_LOCK_PATH"
    
    # Get our own ENR
    OUR_ENR=$(docker run --rm \
        -v "$REPO_ROOT/.charon:/opt/charon/.charon" \
        "obolnetwork/charon:${CHARON_VERSION:-v1.9.0-rc3}" \
        enr 2>/dev/null || echo "")
    
    if [ -n "$OUR_ENR" ]; then
        log_info "  Our ENR: ${OUR_ENR:0:50}..."
    fi
    log_info "  Old ENR: ${OLD_ENR:0:50}..."
    
    echo ""
    
    # Step 2: Copy cluster-lock to .charon for ceremony
    log_step "Step 2: Preparing for ceremony..."
    
    mkdir -p .charon
    if [ "$DRY_RUN" = false ]; then
        cp "$CLUSTER_LOCK_PATH" .charon/cluster-lock.json
        log_info "Cluster-lock copied to .charon/"
    else
        echo "  [DRY-RUN] cp $CLUSTER_LOCK_PATH .charon/cluster-lock.json"
    fi
    
    echo ""
    
    # Step 3: Run ceremony
    log_step "Step 3: Running replace-operator ceremony..."
    log_warn "This requires ALL operators (remaining + you) to run the ceremony simultaneously."
    
    mkdir -p "$OUTPUT_DIR"
    
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
            alpha edit replace-operator \
            --lock-file=/opt/charon/.charon/cluster-lock.json \
            --output-dir=/opt/charon/output \
            --old-operator-enr="$OLD_ENR" \
            --new-operator-enr="$OUR_ENR"
    else
        echo "  [DRY-RUN] docker run --rm ... charon alpha edit replace-operator ..."
    fi
    
    log_info "Ceremony completed successfully"
    
    echo ""
    
    # Step 4: Backup and install new .charon directory
    log_step "Step 4: Installing new cluster configuration..."
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    
    run_cmd mv .charon "$BACKUP_DIR/.charon.$TIMESTAMP"
    log_info "Old .charon backed up to $BACKUP_DIR/.charon.$TIMESTAMP"
    
    run_cmd mv "$OUTPUT_DIR" .charon
    log_info "New configuration installed to .charon/"
    
    # Verify our ENR is in the new cluster-lock
    if [ "$DRY_RUN" = false ] && [ -f .charon/cluster-lock.json ]; then
        if grep -q "${OUR_ENR:0:50}" .charon/cluster-lock.json 2>/dev/null; then
            log_info "Verified: Your ENR is present in the new cluster-lock"
        else
            log_warn "Your ENR may not be in this cluster-lock."
            log_warn "Please verify the ceremony completed successfully."
        fi
        
        # Show cluster info
        NUM_VALIDATORS=$(jq '.distributed_validators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
        NUM_OPERATORS=$(jq '.operators | length' .charon/cluster-lock.json 2>/dev/null || echo "?")
        log_info "Cluster info: $NUM_VALIDATORS validator(s), $NUM_OPERATORS operator(s)"
    fi
    
    echo ""
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Replace-Operator Workflow COMPLETED                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Summary:"
    log_info "  - Old .charon backed up to: $BACKUP_DIR/.charon.$TIMESTAMP"
    log_info "  - New configuration installed to: .charon/"
    echo ""
    log_warn "╔════════════════════════════════════════════════════════════════╗"
    log_warn "║  IMPORTANT: Wait at least 2 epochs (~13 min) before starting   ║"
    log_warn "║  containers to avoid slashing risk from duplicate attestations ║"
    log_warn "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "When ready, start containers with:"
    echo "  docker compose up -d charon $VC"
    echo ""
    log_info "After starting, verify:"
    log_info "  1. Check charon logs: docker compose logs -f charon"
    log_info "  2. Verify VC is running: docker compose logs -f $VC"
    log_info "  3. Monitor validator duties once synced"
    echo ""
    log_warn "Note: As a new operator, you do NOT have any slashing protection history."
    log_warn "Your VC will start fresh."
    echo ""
    log_warn "Keep the backup until you've verified normal operation for several epochs."
    echo ""
    
    exit 0
fi

# Error: missing required arguments
log_error "Missing required arguments."
echo ""
echo "To generate ENR:  --generate-enr"
echo "To run ceremony:  --cluster-lock <path> --old-enr <enr>"
echo ""
echo "Use --help for full usage information."
exit 1
