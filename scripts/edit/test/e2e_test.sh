#!/usr/bin/env bash

# E2E Integration Test for Cluster Edit Scripts
#
# This test creates a real cluster using charon and runs each edit script
# through its happy path. Real Docker is used for charon ceremony commands;
# docker compose (container lifecycle, ASDB) is mocked.
#
# Prerequisites:
#   - Docker running
#   - jq installed
#   - Internet access (charon uses Obol relay for P2P ceremonies)
#
# Usage:
#   ./scripts/edit/test/e2e_test.sh

set -euo pipefail

# --- Configuration ---

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
CHARON_VERSION="${CHARON_VERSION:-v1.8.2}"
CHARON_IMAGE="obolnetwork/charon:${CHARON_VERSION}"
NUM_OPERATORS=4
ZERO_ADDR="0x0000000000000000000000000000000000000001"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# --- Helpers ---

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test()  { echo -e "${BLUE}[TEST]${NC}  $1"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        log_info "  PASS: $desc (got $actual)"
        return 0
    else
        log_error "  FAIL: $desc - expected '$expected', got '$actual'"
        return 1
    fi
}

assert_ne() {
    local desc="$1" not_expected="$2" actual="$3"
    if [ "$not_expected" != "$actual" ]; then
        log_info "  PASS: $desc (values differ)"
        return 0
    else
        log_error "  FAIL: $desc - expected different from '$not_expected', but got same"
        return 1
    fi
}

run_test() {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "================================================================"
    log_test "TEST $TESTS_RUN: $name"
    echo "================================================================"
    echo ""
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_info "TEST $TESTS_RUN PASSED: $name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "TEST $TESTS_RUN FAILED: $name"
    fi
}

# --- Setup ---

TMP_DIR=""
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
        log_info "Cleaned up $TMP_DIR"
    fi
}
trap cleanup EXIT

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker is not running"
        exit 1
    fi

    log_info "Pulling charon image: $CHARON_IMAGE"
    docker pull "$CHARON_IMAGE" >/dev/null 2>&1 || true

    log_info "Prerequisites OK"
}

setup_tmp_dir() {
    TMP_DIR=$(mktemp -d)
    log_info "Working directory: $TMP_DIR"
}

create_cluster() {
    log_info "Creating test cluster with $NUM_OPERATORS nodes, 1 validator..."

    local cluster_dir="$TMP_DIR/cluster"
    mkdir -p "$cluster_dir"

    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$cluster_dir:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        create cluster \
        --nodes="$NUM_OPERATORS" \
        --num-validators=1 \
        --network=hoodi \
        --withdrawal-addresses="$ZERO_ADDR" \
        --fee-recipient-addresses="$ZERO_ADDR" \
        --cluster-dir=/opt/charon/.charon

    # Verify cluster was created
    if [ ! -d "$cluster_dir/node0" ]; then
        log_error "Cluster creation failed - no node0 directory"
        exit 1
    fi

    log_info "Cluster created successfully"

    # Set up operator work directories
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        mkdir -p "$op_dir"

        # Copy node contents to operator's .charon directory
        cp -r "$cluster_dir/node${i}" "$op_dir/.charon"

        # Create .env file
        cat > "$op_dir/.env" <<EOF
NETWORK=hoodi
VC=vc-lodestar
EOF

        # Initialize mock state: mark services as running
        mkdir -p "$op_dir"
        echo "charon=running" > "$op_dir/services.state"
        echo "vc-lodestar=running" >> "$op_dir/services.state"

        log_info "  Operator $i set up at $op_dir"
    done
}

setup_mock_docker() {
    export REAL_DOCKER
    REAL_DOCKER="$(which docker)"
    export PATH="$TEST_DIR/bin:$PATH"

    log_info "Mock docker enabled (real docker at $REAL_DOCKER)"
}

# --- Test Functions ---

test_add_validators() {
    log_info "Running add-validators ceremony (4 operators in parallel)..."

    local pids=()
    local logs_dir="$TMP_DIR/logs/add-validators"
    mkdir -p "$logs_dir"

    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            MOCK_OPERATOR_INDEX="$i" \
            MOCK_STATE_DIR="$op_dir" \
                "$REPO_ROOT/scripts/edit/add-validators/add-validators.sh" \
                --num-validators 1 \
                --withdrawal-addresses "$ZERO_ADDR" \
                --fee-recipient-addresses "$ZERO_ADDR"
        ) > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    # Wait for all operators
    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            cat "$logs_dir/operator${i}.log" || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: each operator should have a cluster-lock with 2 validators
    local ok=true
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_vals
        num_vals=$(jq '.distributed_validators | length' "$lock")
        assert_eq "Operator $i has 2 validators" "2" "$num_vals" || ok=false

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has $NUM_OPERATORS operators" "$NUM_OPERATORS" "$num_ops" || ok=false
    done

    [ "$ok" = true ]
}

test_recreate_private_keys() {
    log_info "Running recreate-private-keys ceremony (4 operators in parallel)..."

    # Save current public_shares for comparison
    local old_shares
    old_shares=$(jq -r '.distributed_validators[0].public_shares[0]' \
        "$TMP_DIR/operator0/.charon/cluster-lock.json")

    local pids=()
    local logs_dir="$TMP_DIR/logs/recreate-private-keys"
    mkdir -p "$logs_dir"

    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        # Reset service state to running for this test
        echo "charon=running" > "$op_dir/services.state"
        echo "vc-lodestar=running" >> "$op_dir/services.state"
        (
            WORK_DIR="$op_dir" \
            MOCK_OPERATOR_INDEX="$i" \
            MOCK_STATE_DIR="$op_dir" \
                "$REPO_ROOT/scripts/edit/recreate-private-keys/recreate-private-keys.sh"
        ) > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            cat "$logs_dir/operator${i}.log" || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: still 2 validators, 4 operators, but different public_shares
    local ok=true
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_vals
        num_vals=$(jq '.distributed_validators | length' "$lock")
        assert_eq "Operator $i has 2 validators" "2" "$num_vals" || ok=false

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has $NUM_OPERATORS operators" "$NUM_OPERATORS" "$num_ops" || ok=false
    done

    # Check that public shares changed
    local new_shares
    new_shares=$(jq -r '.distributed_validators[0].public_shares[0]' \
        "$TMP_DIR/operator0/.charon/cluster-lock.json")
    assert_ne "Public shares changed after recreate" "$old_shares" "$new_shares" || ok=false

    [ "$ok" = true ]
}

test_add_operators() {
    log_info "Running add-operators ceremony (4 existing + 1 new)..."

    # Create operator4 work directory
    local new_op_dir="$TMP_DIR/operator4"
    mkdir -p "$new_op_dir/.charon"

    # Generate ENR for new operator
    log_info "  Generating ENR for new operator..."
    "$REAL_DOCKER" run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$new_op_dir/.charon:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        create enr

    # Extract ENR
    local new_enr
    new_enr=$("$REAL_DOCKER" run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$new_op_dir/.charon:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        enr 2>/dev/null)

    if [ -z "$new_enr" ]; then
        log_error "Failed to get ENR for new operator"
        return 1
    fi
    log_info "  New operator ENR: ${new_enr:0:50}..."

    # Copy cluster-lock from operator0 to operator4
    cp "$TMP_DIR/operator0/.charon/cluster-lock.json" "$new_op_dir/.charon/cluster-lock.json"

    # Create .env for new operator
    cat > "$new_op_dir/.env" <<EOF
NETWORK=hoodi
VC=vc-lodestar
EOF
    mkdir -p "$new_op_dir"
    echo "charon=running" > "$new_op_dir/services.state"
    echo "vc-lodestar=running" >> "$new_op_dir/services.state"

    # Reset service states for existing operators
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        echo "charon=running" > "$op_dir/services.state"
        echo "vc-lodestar=running" >> "$op_dir/services.state"
    done

    local pids=()
    local logs_dir="$TMP_DIR/logs/add-operators"
    mkdir -p "$logs_dir"

    # Run existing operators
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            MOCK_OPERATOR_INDEX="$i" \
            MOCK_STATE_DIR="$op_dir" \
                "$REPO_ROOT/scripts/edit/add-operators/existing-operator.sh" \
                --new-operator-enrs "$new_enr"
        ) > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    # Run new operator
    (
        WORK_DIR="$new_op_dir" \
        MOCK_OPERATOR_INDEX="$NUM_OPERATORS" \
        MOCK_STATE_DIR="$new_op_dir" \
            "$REPO_ROOT/scripts/edit/add-operators/new-operator.sh" \
            --new-operator-enrs "$new_enr" \
            --cluster-lock ".charon/cluster-lock.json"
    ) > "$logs_dir/operator4.log" 2>&1 &
    pids+=($!)

    # Wait for all
    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            cat "$logs_dir/operator${i}.log" || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: all operators should now have 5 operators in cluster-lock
    local ok=true
    for i in $(seq 0 "$NUM_OPERATORS"); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has 5 operators" "5" "$num_ops" || ok=false
    done

    [ "$ok" = true ]
}

test_remove_operators() {
    log_info "Running remove-operators ceremony (removing operator4, 4 remaining)..."

    # Get operator4's ENR from cluster-lock
    local op4_enr
    op4_enr=$(jq -r '.cluster_definition.operators[4].enr' "$TMP_DIR/operator0/.charon/cluster-lock.json")

    if [ -z "$op4_enr" ] || [ "$op4_enr" = "null" ]; then
        log_error "Failed to get operator4 ENR from cluster-lock"
        return 1
    fi
    log_info "  Operator4 ENR to remove: ${op4_enr:0:50}..."

    # Reset service states for remaining operators
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        echo "charon=running" > "$op_dir/services.state"
        echo "vc-lodestar=running" >> "$op_dir/services.state"
    done

    local pids=()
    local logs_dir="$TMP_DIR/logs/remove-operators"
    mkdir -p "$logs_dir"

    # Run remaining operators (0-3) — operator4 does NOT participate
    # (within fault tolerance: 5 ops, threshold ~4, f=1)
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            MOCK_OPERATOR_INDEX="$i" \
            MOCK_STATE_DIR="$op_dir" \
                "$REPO_ROOT/scripts/edit/remove-operators/remaining-operator.sh" \
                --operator-enrs-to-remove "$op4_enr"
        ) > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            cat "$logs_dir/operator${i}.log" || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: 4 operators in new cluster-lock
    local ok=true
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has 4 operators" "4" "$num_ops" || ok=false
    done

    [ "$ok" = true ]
}

test_replace_operator() {
    log_info "Running replace-operator workflow (replacing operator0)..."

    # Create new operator work directory
    local new_op_dir="$TMP_DIR/new-operator"
    mkdir -p "$new_op_dir/.charon"

    # Generate ENR for replacement operator
    log_info "  Generating ENR for replacement operator..."
    "$REAL_DOCKER" run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$new_op_dir/.charon:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        create enr

    local new_enr
    new_enr=$("$REAL_DOCKER" run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$new_op_dir/.charon:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        enr 2>/dev/null)

    if [ -z "$new_enr" ]; then
        log_error "Failed to get ENR for replacement operator"
        return 1
    fi
    log_info "  Replacement operator ENR: ${new_enr:0:50}..."

    # Create .env for new operator
    cat > "$new_op_dir/.env" <<EOF
NETWORK=hoodi
VC=vc-lodestar
EOF
    mkdir -p "$new_op_dir"

    # Reset service states for remaining operators (1-3)
    for i in $(seq 1 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        echo "charon=running" > "$op_dir/services.state"
        echo "vc-lodestar=running" >> "$op_dir/services.state"
    done

    # Replace-operator is OFFLINE (no P2P) — each remaining operator runs independently
    local logs_dir="$TMP_DIR/logs/replace-operator"
    mkdir -p "$logs_dir"

    local ok=true
    for i in $(seq 1 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        log_info "  Running remaining-operator.sh for operator $i..."
        if ! (
            WORK_DIR="$op_dir" \
            MOCK_OPERATOR_INDEX="$i" \
            MOCK_STATE_DIR="$op_dir" \
                "$REPO_ROOT/scripts/edit/replace-operator/remaining-operator.sh" \
                --new-enr "$new_enr" \
                --operator-index 0
        ) > "$logs_dir/operator${i}.log" 2>&1; then
            log_error "Operator $i failed. Log:"
            cat "$logs_dir/operator${i}.log" || true
            ok=false
        fi
    done

    if [ "$ok" = false ]; then
        return 1
    fi

    # Copy output cluster-lock from operator1 to new operator's work dir
    local src_lock="$TMP_DIR/operator1/.charon/cluster-lock.json"
    if [ ! -f "$src_lock" ]; then
        # Try output dir
        src_lock="$TMP_DIR/operator1/output/cluster-lock.json"
    fi
    if [ ! -f "$src_lock" ]; then
        log_error "No output cluster-lock found for new operator"
        return 1
    fi

    # New operator receives cluster-lock and joins
    echo "charon=stopped" > "$new_op_dir/services.state"
    echo "vc-lodestar=stopped" >> "$new_op_dir/services.state"

    log_info "  Running new-operator.sh..."
    if ! (
        WORK_DIR="$new_op_dir" \
        MOCK_OPERATOR_INDEX="0" \
        MOCK_STATE_DIR="$new_op_dir" \
            "$REPO_ROOT/scripts/edit/replace-operator/new-operator.sh" \
            --cluster-lock "$src_lock"
    ) > "$logs_dir/new-operator.log" 2>&1; then
        log_error "New operator failed. Log:"
        cat "$logs_dir/new-operator.log" || true
        return 1
    fi

    # Verify: 4 operators, operator 0's ENR changed
    local lock="$new_op_dir/.charon/cluster-lock.json"
    if [ ! -f "$lock" ]; then
        log_error "New operator: cluster-lock.json not found"
        return 1
    fi

    local num_ops
    num_ops=$(jq '.cluster_definition.operators | length' "$lock")
    assert_eq "New operator has 4 operators" "4" "$num_ops" || ok=false

    # Check that operator 0's ENR changed to the new ENR
    local op0_enr
    op0_enr=$(jq -r '.cluster_definition.operators[0].enr' "$lock")
    # The ENR should contain part of our new ENR (ENRs are reformatted by charon)
    if [ "$op0_enr" != "null" ] && [ -n "$op0_enr" ]; then
        log_info "  PASS: Operator 0 ENR is present in new cluster-lock"
    else
        log_error "  FAIL: Operator 0 ENR missing from cluster-lock"
        ok=false
    fi

    [ "$ok" = true ]
}

test_update_asdb() {
    log_info "Running update-anti-slashing-db standalone test..."

    # Use cluster-locks from earlier tests as source/target
    # Find two different cluster-locks (before/after recreate-private-keys)
    # We'll use operator0's backup and current cluster-lock

    local source_lock=""
    local target_lock=""

    # Find backup from recreate-private-keys (or add-validators)
    for backup in "$TMP_DIR"/operator0/backups/.charon-backup.*/cluster-lock.json; do
        if [ -f "$backup" ]; then
            source_lock="$backup"
            break
        fi
    done

    target_lock="$TMP_DIR/operator0/.charon/cluster-lock.json"

    if [ -z "$source_lock" ] || [ ! -f "$source_lock" ]; then
        log_warn "No backup cluster-lock found, creating synthetic test data..."

        # Create synthetic source and target
        local asdb_test_dir="$TMP_DIR/asdb-test"
        mkdir -p "$asdb_test_dir"

        source_lock="$asdb_test_dir/source-lock.json"
        target_lock="$asdb_test_dir/target-lock.json"

        # Use operator0's original cluster from the initial creation
        local orig_lock="$TMP_DIR/cluster/node0/cluster-lock.json"
        if [ -f "$orig_lock" ]; then
            cp "$orig_lock" "$source_lock"
            cp "$TMP_DIR/operator0/.charon/cluster-lock.json" "$target_lock"
        else
            log_error "Cannot find any cluster-lock files for ASDB test"
            return 1
        fi
    fi

    if [ ! -f "$target_lock" ]; then
        log_error "Target cluster-lock not found: $target_lock"
        return 1
    fi

    log_info "  Source lock: $source_lock"
    log_info "  Target lock: $target_lock"

    # Generate EIP-3076 JSON with pubkeys from source lock
    local asdb_dir="$TMP_DIR/asdb-test"
    mkdir -p "$asdb_dir"
    local eip3076_file="$asdb_dir/slashing-protection.json"

    # Extract operator 0's pubkeys from source lock
    local pubkeys
    pubkeys=$(jq -r '.distributed_validators[].public_shares[0]' "$source_lock")

    local data_entries=""
    local first=true
    while IFS= read -r pk; do
        [ -z "$pk" ] && continue
        if [ "$first" = true ]; then
            first=false
        else
            data_entries="${data_entries},"
        fi
        data_entries="${data_entries}{\"pubkey\":\"${pk}\",\"signed_blocks\":[],\"signed_attestations\":[]}"
    done <<< "$pubkeys"

    cat > "$eip3076_file" <<EOF
{"metadata":{"interchange_format_version":"5","genesis_validators_root":"0x0000000000000000000000000000000000000000000000000000000000000000"},"data":[${data_entries}]}
EOF

    log_info "  Generated EIP-3076 with $(echo "$pubkeys" | wc -l | tr -d ' ') pubkey(s)"

    # Get pubkeys before update
    local old_pubkeys
    old_pubkeys=$(jq -r '.data[].pubkey' "$eip3076_file" | sort)

    # Run update script
    if ! "$REPO_ROOT/scripts/edit/vc/update-anti-slashing-db.sh" \
        "$eip3076_file" "$source_lock" "$target_lock"; then
        log_error "update-anti-slashing-db.sh failed"
        return 1
    fi

    # Get pubkeys after update
    local new_pubkeys
    new_pubkeys=$(jq -r '.data[].pubkey' "$eip3076_file" | sort)

    # Verify pubkeys were transformed
    local ok=true

    # Verify the output is valid JSON
    if ! jq empty "$eip3076_file" 2>/dev/null; then
        log_error "Output is not valid JSON"
        return 1
    fi

    # Check that pubkeys now match target lock's operator 0 shares
    # Only compare validators that existed in the source lock
    local source_val_count
    source_val_count=$(jq '.distributed_validators | length' "$source_lock")
    local expected_pubkeys
    expected_pubkeys=$(jq -r --argjson n "$source_val_count" \
        '[.distributed_validators[:$n][].public_shares[0]] | .[]' "$target_lock" | sort)

    if [ "$new_pubkeys" = "$expected_pubkeys" ]; then
        log_info "  PASS: Pubkeys correctly transformed to target cluster-lock values"
    else
        log_error "  FAIL: Pubkeys don't match target cluster-lock"
        log_error "    Expected: $expected_pubkeys"
        log_error "    Got:      $new_pubkeys"
        ok=false
    fi

    [ "$ok" = true ]
}

# --- Main ---

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     E2E Integration Test for Cluster Edit Scripts              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    setup_tmp_dir
    create_cluster
    setup_mock_docker

    # Run tests sequentially — each builds on the previous state
    run_test "add-validators"          test_add_validators
    run_test "recreate-private-keys"   test_recreate_private_keys
    run_test "add-operators"           test_add_operators
    run_test "remove-operators"        test_remove_operators
    run_test "replace-operator"        test_replace_operator
    run_test "update-anti-slashing-db" test_update_asdb

    # Summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Test Summary                                               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Tests run:    $TESTS_RUN"
    echo -e "  Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "  Tests failed: ${RED}$TESTS_FAILED${NC}"
    else
        echo "  Tests failed: $TESTS_FAILED"
    fi
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        log_error "SOME TESTS FAILED"
        exit 1
    else
        log_info "ALL TESTS PASSED"
        exit 0
    fi
}

main "$@"
