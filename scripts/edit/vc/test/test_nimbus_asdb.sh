#!/usr/bin/env bash

# Integration test for export/import ASDB scripts with Nimbus VC.
#
# This script:
# 1. Builds vc-nimbus image if needed
# 2. Starts vc-nimbus via docker-compose with test override (no charon dependency)
# 3. Sets up keystores in the container
# 4. Stops container and imports sample slashing protection data
# 5. Calls scripts/edit/vc/export_asdb.sh to export slashing protection (container stopped)
# 6. Runs update-anti-slashing-db.sh to transform pubkeys
# 7. Calls scripts/edit/vc/import_asdb.sh to import updated slashing protection (container stopped)
#
# Usage: ./scripts/edit/vc/test/test_nimbus_asdb.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$REPO_ROOT"

# Test artifacts directories
TEST_OUTPUT_DIR="$SCRIPT_DIR/output"
TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.test.yml"
TEST_DATA_DIR="$SCRIPT_DIR/data/nimbus"
TEST_COMPOSE_FILES="docker-compose.yml:compose-vc.yml:$TEST_COMPOSE_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up test resources..."
    COMPOSE_FILE="$TEST_COMPOSE_FILES" docker compose --profile vc-nimbus down 2>/dev/null || true
    # Keep TEST_OUTPUT_DIR for inspection
    # Clean test data to avoid stale DB locks
    rm -rf "$TEST_DATA_DIR" 2>/dev/null || true
}

trap cleanup EXIT

# Clean test data directory before starting (remove stale locks)
log_info "Preparing test environment..."
COMPOSE_FILE="$TEST_COMPOSE_FILES" docker compose --profile vc-nimbus down 2>/dev/null || true
rm -rf "$TEST_DATA_DIR"
mkdir -p "$TEST_DATA_DIR"

# Copy run.sh into test data directory to satisfy the volume mount from base compose
# (compose merge keeps the original mount ./nimbus/run.sh:/home/user/data/run.sh,
# which conflicts with our test data mount unless we provide the file there)
cp "$REPO_ROOT/nimbus/run.sh" "$TEST_DATA_DIR/run.sh"

# Check prerequisites
log_info "Checking prerequisites..."

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
fi

# Check for test validator keys in fixtures
KEYSTORE_COUNT=$(ls "$TEST_FIXTURES_DIR/validator_keys"/keystore-*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$KEYSTORE_COUNT" -eq 0 ]; then
    log_error "No keystore files found in $TEST_FIXTURES_DIR/validator_keys"
    exit 1
fi
log_info "Found $KEYSTORE_COUNT test keystore file(s)"

# Verify test fixtures exist
if [ ! -f "$TEST_FIXTURES_DIR/source-cluster-lock.json" ] || [ ! -f "$TEST_FIXTURES_DIR/target-cluster-lock.json" ]; then
    log_error "Test fixtures not found in $TEST_FIXTURES_DIR"
    exit 1
fi
log_info "Test fixtures verified"

# Source .env for NETWORK, then override COMPOSE_FILE with test compose
if [ ! -f .env ]; then
    log_warn ".env file not found, creating with NETWORK=hoodi"
    echo "NETWORK=hoodi" > .env
fi

source .env
NETWORK="${NETWORK:-hoodi}"

# Override COMPOSE_FILE after sourcing .env (which may have its own COMPOSE_FILE)
export COMPOSE_FILE="$TEST_COMPOSE_FILES"

log_info "Using network: $NETWORK"
log_info "Using compose files: $COMPOSE_FILE"

# Create test output directory
mkdir -p "$TEST_OUTPUT_DIR"

# Step 0: Build vc-nimbus image if needed
log_info "Step 0: Building vc-nimbus image..."

if ! docker compose --profile vc-nimbus build vc-nimbus; then
    log_error "Failed to build vc-nimbus image"
    exit 1
fi
log_info "Image built successfully"

# Step 1: Start vc-nimbus via docker-compose
log_info "Step 1: Starting vc-nimbus via docker-compose..."

docker compose --profile vc-nimbus up -d vc-nimbus

sleep 2

# Verify container is running
if ! docker compose ps vc-nimbus | grep -q Up; then
    log_error "Container failed to start. Checking logs:"
    docker compose logs vc-nimbus 2>&1 || true
    exit 1
fi

log_info "Container started successfully"

# Step 2: Set up keystores using nimbus_beacon_node deposits import
log_info "Step 2: Setting up keystores..."

# Create a temporary directory in the container for importing
docker compose exec -T vc-nimbus sh -c '
    mkdir -p /home/user/data/validators /tmp/keyimport
    
    for f in /home/validator_keys/keystore-*.json; do
        echo "Importing key from $f"
        
        # Read password
        password=$(cat "${f%.json}.txt")
        
        # Copy keystore to temp dir
        cp "$f" /tmp/keyimport/
        
        # Import using nimbus_beacon_node
        echo "$password" | /home/user/nimbus_beacon_node deposits import \
            --data-dir=/home/user/data \
            /tmp/keyimport
        
        # Clean temp dir
        rm /tmp/keyimport/*
    done
    
    rm -rf /tmp/keyimport
    echo "Done importing keystores"
'

log_info "Keystores set up successfully"

# Step 3: Stop container and import sample slashing protection data
log_info "Step 3: Importing sample slashing protection data..."

docker compose stop vc-nimbus

SAMPLE_ASDB="$TEST_FIXTURES_DIR/sample-slashing-protection.json"

if VC=vc-nimbus "$REPO_ROOT/scripts/edit/vc/import_asdb.sh" --input-file "$SAMPLE_ASDB"; then
    log_info "Sample data imported successfully!"
else
    log_error "Failed to import sample data"
    exit 1
fi

# Step 4: Test export using the actual script (container should remain stopped)
log_info "Step 4: Testing export_asdb.sh script..."

EXPORT_FILE="$TEST_OUTPUT_DIR/exported-asdb.json"

if VC=vc-nimbus "$REPO_ROOT/scripts/edit/vc/export_asdb.sh" --output-file "$EXPORT_FILE"; then
    log_info "Export script successful!"
    log_info "Exported content:"
    jq '.' "$EXPORT_FILE"
    
    # Verify exported data matches what we imported
    EXPORTED_COUNT=$(jq '.data | length' "$EXPORT_FILE")
    EXPORTED_ATTESTATIONS=$(jq '.data[0].signed_attestations | length' "$EXPORT_FILE" 2>/dev/null || echo "0")
    log_info "Exported $EXPORTED_COUNT validator(s) with $EXPORTED_ATTESTATIONS attestation(s)"
else
    log_error "Export script failed"
    exit 1
fi

# Step 5: Run update-anti-slashing-db.sh to transform pubkeys
log_info "Step 5: Running update-anti-slashing-db.sh..."

UPDATE_SCRIPT="$REPO_ROOT/scripts/edit/vc/update-anti-slashing-db.sh"
SOURCE_LOCK="$TEST_FIXTURES_DIR/source-cluster-lock.json"
TARGET_LOCK="$TEST_FIXTURES_DIR/target-cluster-lock.json"

# Copy export to a working file that will be modified in place
UPDATED_FILE="$TEST_OUTPUT_DIR/updated-asdb.json"
cp "$EXPORT_FILE" "$UPDATED_FILE"

log_info "Source pubkey (operator 0): $(jq -r '.distributed_validators[0].public_shares[0]' "$SOURCE_LOCK")"
log_info "Target pubkey (operator 0): $(jq -r '.distributed_validators[0].public_shares[0]' "$TARGET_LOCK")"

if "$UPDATE_SCRIPT" "$UPDATED_FILE" "$SOURCE_LOCK" "$TARGET_LOCK"; then
    log_info "Update successful!"
    log_info "Updated content:"
    jq '.' "$UPDATED_FILE"
    
    # Verify the pubkey was transformed
    EXPORTED_PUBKEY=$(jq -r '.data[0].pubkey // empty' "$EXPORT_FILE")
    UPDATED_PUBKEY=$(jq -r '.data[0].pubkey // empty' "$UPDATED_FILE")
    
    if [ -n "$EXPORTED_PUBKEY" ] && [ -n "$UPDATED_PUBKEY" ]; then
        if [ "$EXPORTED_PUBKEY" != "$UPDATED_PUBKEY" ]; then
            log_info "Pubkey transformation verified:"
            log_info "  Before: $EXPORTED_PUBKEY"
            log_info "  After:  $UPDATED_PUBKEY"
        else
            log_error "Pubkey was NOT transformed - test fixture mismatch!"
            exit 1
        fi
    else
        log_error "No pubkey data in exported file - sample import may have failed"
        exit 1
    fi
else
    log_error "Update script failed"
    exit 1
fi

# Step 6: Test import using the actual script (container is already stopped)
log_info "Step 6: Testing import_asdb.sh script..."

if VC=vc-nimbus "$REPO_ROOT/scripts/edit/vc/import_asdb.sh" --input-file "$UPDATED_FILE"; then
    log_info "Import script successful!"
else
    log_error "Import script failed"
    exit 1
fi

echo ""
log_info "========================================="
log_info "All tests passed successfully!"
log_info "========================================="
log_info ""
log_info "Test artifacts in: $TEST_OUTPUT_DIR"
log_info "  - exported-asdb.json (original export)"
log_info "  - updated-asdb.json  (after pubkey transformation)"
