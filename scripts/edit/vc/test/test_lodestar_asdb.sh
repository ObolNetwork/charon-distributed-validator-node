#!/usr/bin/env bash

# Integration test for export/import ASDB scripts with Lodestar VC.
#
# This script:
# 1. Starts vc-lodestar via docker-compose with test override (no charon dependency)
# 2. Sets up keystores in the container
# 3. Imports sample slashing protection data (with known pubkey and attestations)
# 4. Calls scripts/edit/vc/export_asdb.sh to export slashing protection
# 5. Runs update-anti-slashing-db.sh to transform pubkeys
# 6. Stops the container
# 7. Calls scripts/edit/vc/import_asdb.sh to import updated slashing protection
#
# Usage: ./scripts/edit/vc/test/test_lodestar_asdb.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$REPO_ROOT"

# Test artifacts directories
TEST_OUTPUT_DIR="$SCRIPT_DIR/output"
TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.test.yml"
TEST_DATA_DIR="$SCRIPT_DIR/data/lodestar"
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
    COMPOSE_FILE="$TEST_COMPOSE_FILES" docker compose --profile vc-lodestar down 2>/dev/null || true
    # Keep TEST_OUTPUT_DIR for inspection
    # Clean test data to avoid stale DB locks
    rm -rf "$TEST_DATA_DIR" 2>/dev/null || true
}

trap cleanup EXIT

# Clean test data directory before starting (remove stale locks)
log_info "Preparing test environment..."
COMPOSE_FILE="$TEST_COMPOSE_FILES" docker compose --profile vc-lodestar down 2>/dev/null || true
rm -rf "$TEST_DATA_DIR"
mkdir -p "$TEST_DATA_DIR"

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

# Step 1: Start vc-lodestar via docker-compose
log_info "Step 1: Starting vc-lodestar via docker-compose..."

docker compose --profile vc-lodestar up -d vc-lodestar

sleep 2

# Verify container is running
if ! docker compose ps vc-lodestar | grep -q Up; then
    log_error "Container failed to start. Checking logs:"
    docker compose logs vc-lodestar 2>&1 || true
    exit 1
fi

log_info "Container started successfully"

# Step 2: Set up keystores (normally done by run.sh but we override entrypoint)
log_info "Step 2: Setting up keystores..."

docker compose exec -T vc-lodestar sh -c '
    mkdir -p /opt/data/keystores /opt/data/secrets
    for f in /home/charon/validator_keys/keystore-*.json; do
        PUBKEY="0x$(grep "\"pubkey\"" "$f" | sed "s/.*: *\"\([^\"]*\)\".*/\1/")"
        mkdir -p "/opt/data/keystores/$PUBKEY"
        cp "$f" "/opt/data/keystores/$PUBKEY/voting-keystore.json"
        cp "${f%.json}.txt" "/opt/data/secrets/$PUBKEY"
        echo "Imported keystore for $PUBKEY"
    done
'

log_info "Keystores set up successfully"

# Step 3: Stop container and import sample slashing protection data
log_info "Step 3: Importing sample slashing protection data..."

docker compose stop vc-lodestar

SAMPLE_ASDB="$TEST_FIXTURES_DIR/sample-slashing-protection.json"

if VC=vc-lodestar "$REPO_ROOT/scripts/edit/vc/import_asdb.sh" --input-file "$SAMPLE_ASDB"; then
    log_info "Sample data imported successfully!"
else
    log_error "Failed to import sample data"
    exit 1
fi

# Start container again for export
docker compose --profile vc-lodestar up -d vc-lodestar
sleep 2

# Clean stale LevelDB lock file from previous import run
docker compose exec -T vc-lodestar rm -f /opt/data/validator-db/LOCK 2>/dev/null || true

# Step 4: Test export using the actual script
log_info "Step 4: Testing export_asdb.sh script..."

EXPORT_FILE="$TEST_OUTPUT_DIR/exported-asdb.json"

if VC=vc-lodestar "$REPO_ROOT/scripts/edit/vc/export_asdb.sh" --output-file "$EXPORT_FILE"; then
    log_info "Export script successful!"
    log_info "Exported content:"
    jq '.' "$EXPORT_FILE"
    
    # Verify exported data matches what we imported
    EXPORTED_COUNT=$(jq '.data | length' "$EXPORT_FILE")
    EXPORTED_ATTESTATIONS=$(jq '.data[0].signed_attestations | length' "$EXPORT_FILE")
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

# Step 6: Stop container before import (required by import script)
log_info "Step 6: Stopping vc-lodestar for import..."

docker compose stop vc-lodestar

# Step 7: Test import using the actual script
log_info "Step 7: Testing import_asdb.sh script..."

if VC=vc-lodestar "$REPO_ROOT/scripts/edit/vc/import_asdb.sh" --input-file "$UPDATED_FILE"; then
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
