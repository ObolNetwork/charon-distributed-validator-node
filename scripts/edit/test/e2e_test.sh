#!/usr/bin/env bash

# E2E Integration Test for Cluster Edit Scripts
#
# This test uses real Docker Compose services (busybox for charon, real lodestar
# for ASDB operations) and real charon ceremonies via P2P relay.
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
CHARON_VERSION="${CHARON_VERSION:-v1.9.0-rc3}"
CHARON_IMAGE="obolnetwork/charon:${CHARON_VERSION}"
LODESTAR_IMAGE="chainsafe/lodestar:${VC_LODESTAR_VERSION:-v1.38.0}"
NUM_OPERATORS=4
ZERO_ADDR="0x0000000000000000000000000000000000000001"
HOODI_GVR="0x212f13fc4df078b6cb7db228f1c8307566dcecf900867401a92023d7ba99cb5f"

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

# Track active compose projects for cleanup
ACTIVE_PROJECTS=()

# --- Helpers ---

log_info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
log_test()  { printf "${BLUE}[TEST]${NC}  %s\n" "$1"; }

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

# --- Compose helpers ---

# Returns env vars for docker compose targeting operator i's directory.
compose_env() {
    local i="$1"
    local op_dir="$TMP_DIR/operator${i}"
    echo "COMPOSE_FILE=$op_dir/docker-compose.e2e.yml" \
         "COMPOSE_PROJECT_NAME=e2e-op${i}"
}

# Runs docker compose for operator i.
compose_cmd() {
    local i="$1"
    shift
    local op_dir="$TMP_DIR/operator${i}"
    COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
    COMPOSE_PROJECT_NAME="e2e-op${i}" \
        docker compose "$@"
}

start_operator() {
    local i="$1"
    log_info "  Starting compose stack for operator $i..."
    compose_cmd "$i" up -d 2>/dev/null
    # Track this project for cleanup
    local project="e2e-op${i}"
    if ! printf '%s\n' "${ACTIVE_PROJECTS[@]}" 2>/dev/null | grep -qx "$project"; then
        ACTIVE_PROJECTS+=("$project")
    fi
}

stop_operator() {
    local i="$1"
    log_info "  Stopping compose stack for operator $i..."
    compose_cmd "$i" down --remove-orphans 2>/dev/null || true
}

# Generate and import a minimal EIP-3076 ASDB for operator i.
seed_asdb() {
    local op_dir="$1"
    local op_index="$2"
    local lock="$op_dir/.charon/cluster-lock.json"

    if [ ! -f "$lock" ]; then
        log_warn "  No cluster-lock.json for ASDB seed at $op_dir"
        return 0
    fi

    # Extract this operator's public shares
    local pubkeys
    pubkeys=$(jq -r --argjson idx "$op_index" \
        '[.distributed_validators[].public_shares[$idx]] | map(select(. != null)) | .[]' \
        "$lock" 2>/dev/null || echo "")

    if [ -z "$pubkeys" ]; then
        log_warn "  No pubkeys found for operator $op_index, skipping ASDB seed"
        return 0
    fi

    # Build EIP-3076 JSON
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

    local asdb_file="$op_dir/asdb-seed.json"
    cat > "$asdb_file" <<EOF
{"metadata":{"interchange_format_version":"5","genesis_validators_root":"${HOODI_GVR}"},"data":[${data_entries}]}
EOF

    # Make path absolute for docker mount
    local abs_asdb_file
    abs_asdb_file="$(cd "$(dirname "$asdb_file")" && pwd)/$(basename "$asdb_file")"

    # Import into lodestar via docker compose run
    COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
    COMPOSE_PROJECT_NAME="e2e-op${op_index}" \
        docker compose run --rm -T \
        --entrypoint node \
        -v "$abs_asdb_file":/tmp/import.json:ro \
        vc-lodestar /usr/app/packages/cli/bin/lodestar validator slashing-protection import \
        --file /tmp/import.json \
        --dataDir /opt/data \
        --network hoodi \
        --force >/dev/null 2>&1 || log_warn "  ASDB seed import returned non-zero for operator $op_index (may be OK on first run)"

    log_info "  ASDB seeded for operator $op_index"
}

# Restart containers and re-seed ASDB for an operator.
restart_and_seed() {
    local i="$1"
    local op_dir="$TMP_DIR/operator${i}"
    compose_cmd "$i" down --remove-orphans 2>/dev/null || true
    start_operator "$i"
    seed_asdb "$op_dir" "$i"
}

# Set up an operator directory with .charon, .env, compose file, and data dirs.
setup_operator() {
    local i="$1"
    local charon_node_dir="$2"
    local op_dir="$TMP_DIR/operator${i}"
    mkdir -p "$op_dir/data/lodestar"

    # Copy node contents to operator's .charon directory
    cp -r "$charon_node_dir" "$op_dir/.charon"

    # Create .env file
    cat > "$op_dir/.env" <<EOF
NETWORK=hoodi
VC=vc-lodestar
EOF

    # Copy test compose file
    cp "$TEST_DIR/docker-compose.e2e.yml" "$op_dir/docker-compose.e2e.yml"

    log_info "  Operator $i set up at $op_dir"
}

# --- Setup ---

TMP_DIR=""
cleanup() {
    echo ""
    log_info "Cleaning up..."

    # Stop all compose projects
    for project in "${ACTIVE_PROJECTS[@]}"; do
        log_info "  Stopping project $project..."
        COMPOSE_PROJECT_NAME="$project" docker compose down --remove-orphans 2>/dev/null || true
    done

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

    log_info "Pulling images..."
    docker pull "$CHARON_IMAGE" >/dev/null 2>&1 || true
    docker pull "$LODESTAR_IMAGE" >/dev/null 2>&1 || true
    docker pull busybox:latest >/dev/null 2>&1 || true

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

    if [ ! -d "$cluster_dir/node0" ]; then
        log_error "Cluster creation failed - no node0 directory"
        exit 1
    fi

    log_info "Cluster created successfully"

    # Set up operator work directories
    # Note: deposit-data*.json files are inside each node directory,
    # so setup_operator copies them along with the rest of the node contents.
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        setup_operator "$i" "$cluster_dir/node${i}"
    done
}

start_all_operators() {
    local max_idx="${1:-$((NUM_OPERATORS - 1))}"
    log_info "Starting compose stacks for operators 0-${max_idx}..."
    for i in $(seq 0 "$max_idx"); do
        start_operator "$i"
    done
}

seed_all_operators() {
    local max_idx="${1:-$((NUM_OPERATORS - 1))}"
    log_info "Seeding ASDB for operators 0-${max_idx}..."
    for i in $(seq 0 "$max_idx"); do
        seed_asdb "$TMP_DIR/operator${i}" "$i"
    done
}

restart_and_seed_all() {
    local max_idx="${1:-$((NUM_OPERATORS - 1))}"
    log_info "Restarting and re-seeding operators 0-${max_idx}..."
    for i in $(seq 0 "$max_idx"); do
        restart_and_seed "$i"
    done
}

# --- Test Functions ---

test_recreate_private_keys() {
    log_info "Running recreate-private-keys ceremony ($NUM_OPERATORS operators in parallel)..."

    # Save current state for comparison
    local old_shares
    old_shares=$(jq -r '.distributed_validators[0].public_shares[0]' \
        "$TMP_DIR/operator0/.charon/cluster-lock.json")
    local expected_vals
    expected_vals=$(jq '.distributed_validators | length' \
        "$TMP_DIR/operator0/.charon/cluster-lock.json")

    local pids=()
    local logs_dir="$TMP_DIR/logs/recreate-private-keys"
    mkdir -p "$logs_dir"

    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
            COMPOSE_PROJECT_NAME="e2e-op${i}" \
                "$REPO_ROOT/scripts/edit/recreate-private-keys/recreate-private-keys.sh"
        ) < /dev/null > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            sed 's/\r$//' "$logs_dir/operator${i}.log" | while IFS= read -r line; do echo "                $line"; done || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: still 1 validator, same operator count, different public_shares
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
        assert_eq "Operator $i has $expected_vals validators" "$expected_vals" "$num_vals" || ok=false

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

test_add_validators() {
    log_info "Running add-validators ceremony ($NUM_OPERATORS operators in parallel)..."

    local pids=()
    local logs_dir="$TMP_DIR/logs/add-validators"
    mkdir -p "$logs_dir"

    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
            COMPOSE_PROJECT_NAME="e2e-op${i}" \
                "$REPO_ROOT/scripts/edit/add-validators/add-validators.sh" \
                --num-validators 1 \
                --withdrawal-addresses "$ZERO_ADDR" \
                --fee-recipient-addresses "$ZERO_ADDR"
        ) < /dev/null > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            sed 's/\r$//' "$logs_dir/operator${i}.log" | while IFS= read -r line; do echo "                $line"; done || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: each operator should have 2 validators
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

test_add_operators() {
    log_info "Running add-operators ceremony ($NUM_OPERATORS existing + 3 new = 7 total)..."

    local new_enrs=()
    local new_ops_start=$NUM_OPERATORS
    local new_ops_end=$((NUM_OPERATORS + 2))  # 3 new operators: 4, 5, 6

    # Create new operator directories and generate ENRs
    for i in $(seq "$new_ops_start" "$new_ops_end"); do
        local new_op_dir="$TMP_DIR/operator${i}"
        mkdir -p "$new_op_dir/.charon" "$new_op_dir/data/lodestar"

        log_info "  Generating ENR for new operator $i..."
        docker run --rm \
            --user "$(id -u):$(id -g)" \
            -v "$new_op_dir/.charon:/opt/charon/.charon" \
            "$CHARON_IMAGE" \
            create enr

        local new_enr
        new_enr=$(docker run --rm \
            --user "$(id -u):$(id -g)" \
            -v "$new_op_dir/.charon:/opt/charon/.charon" \
            "$CHARON_IMAGE" \
            enr 2>/dev/null)

        if [ -z "$new_enr" ]; then
            log_error "Failed to get ENR for new operator $i"
            return 1
        fi
        log_info "  Operator $i ENR: ${new_enr:0:50}..."
        new_enrs+=("$new_enr")

        # Copy cluster-lock from operator0
        cp "$TMP_DIR/operator0/.charon/cluster-lock.json" "$new_op_dir/.charon/cluster-lock.json"

        # Create .env and compose file
        cat > "$new_op_dir/.env" <<EOF
NETWORK=hoodi
VC=vc-lodestar
EOF
        cp "$TEST_DIR/docker-compose.e2e.yml" "$new_op_dir/docker-compose.e2e.yml"

        # Start compose stack and seed ASDB for new operator
        start_operator "$i"
        seed_asdb "$new_op_dir" "$i" 2>/dev/null || true  # May fail for new ops without existing shares
    done

    # Build comma-separated ENR list
    local enr_list
    enr_list=$(IFS=,; echo "${new_enrs[*]}")

    local pids=()
    local logs_dir="$TMP_DIR/logs/add-operators"
    mkdir -p "$logs_dir"

    # Run existing operators
    for i in $(seq 0 $((NUM_OPERATORS - 1))); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
            COMPOSE_PROJECT_NAME="e2e-op${i}" \
                "$REPO_ROOT/scripts/edit/add-operators/existing-operator.sh" \
                --new-operator-enrs "$enr_list"
        ) < /dev/null > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    # Run new operators
    for i in $(seq "$new_ops_start" "$new_ops_end"); do
        local new_op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$new_op_dir" \
            COMPOSE_FILE="$new_op_dir/docker-compose.e2e.yml" \
            COMPOSE_PROJECT_NAME="e2e-op${i}" \
                "$REPO_ROOT/scripts/edit/add-operators/new-operator.sh" \
                --new-operator-enrs "$enr_list" \
                --cluster-lock ".charon/cluster-lock.json"
        ) < /dev/null > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    # Wait for all
    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Process $i failed. Log:"
            sed 's/\r$//' "$logs_dir/operator${i}.log" 2>/dev/null | while IFS= read -r line; do echo "                $line"; done || true
            # Also check new operator logs
            for j in $(seq "$new_ops_start" "$new_ops_end"); do
                if [ -f "$logs_dir/operator${j}.log" ]; then
                    log_error "New operator $j log:"
                    sed 's/\r$//' "$logs_dir/operator${j}.log" 2>/dev/null | while IFS= read -r line; do echo "                $line"; done || true
                fi
            done
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: all 7 operators should have 7 operators in cluster-lock
    local total_ops=$((new_ops_end + 1))  # 7
    local ok=true
    for i in $(seq 0 "$new_ops_end"); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has $total_ops operators" "$total_ops" "$num_ops" || ok=false
    done

    # Update NUM_OPERATORS to reflect new total
    NUM_OPERATORS="$total_ops"

    [ "$ok" = true ]
}

test_remove_operators() {
    log_info "Running remove-operators ceremony (removing operator6, 6 remaining)..."

    local op_to_remove=$((NUM_OPERATORS - 1))  # operator6

    # Get operator6's ENR from cluster-lock
    local remove_enr
    remove_enr=$(jq -r --argjson idx "$op_to_remove" \
        '.cluster_definition.operators[$idx].enr' \
        "$TMP_DIR/operator0/.charon/cluster-lock.json")

    if [ -z "$remove_enr" ] || [ "$remove_enr" = "null" ]; then
        log_error "Failed to get operator${op_to_remove} ENR from cluster-lock"
        return 1
    fi
    log_info "  Operator${op_to_remove} ENR to remove: ${remove_enr:0:50}..."

    local remaining_max=$((op_to_remove - 1))  # operators 0-5

    local pids=()
    local logs_dir="$TMP_DIR/logs/remove-operators"
    mkdir -p "$logs_dir"

    # Run remaining operators (0-5) — operator6 does NOT participate
    for i in $(seq 0 "$remaining_max"); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
            COMPOSE_PROJECT_NAME="e2e-op${i}" \
                "$REPO_ROOT/scripts/edit/remove-operators/remaining-operator.sh" \
                --operator-enrs-to-remove "$remove_enr"
        ) < /dev/null > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Operator $i failed. Log:"
            sed 's/\r$//' "$logs_dir/operator${i}.log" | while IFS= read -r line; do echo "                $line"; done || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: 6 operators in new cluster-lock
    local expected_ops=$((NUM_OPERATORS - 1))
    local ok=true
    for i in $(seq 0 "$remaining_max"); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has $expected_ops operators" "$expected_ops" "$num_ops" || ok=false
    done

    # Clean up removed operator's compose stack
    stop_operator "$op_to_remove"

    # Update NUM_OPERATORS
    NUM_OPERATORS="$expected_ops"

    [ "$ok" = true ]
}

test_replace_operator() {
    local op_to_replace=$((NUM_OPERATORS - 1))  # replace the last operator
    log_info "Running replace-operator ceremony (replacing operator${op_to_replace})..."

    # Get the old operator's ENR from cluster-lock
    local old_enr
    old_enr=$(jq -r --argjson idx "$op_to_replace" \
        '.cluster_definition.operators[$idx].enr' \
        "$TMP_DIR/operator0/.charon/cluster-lock.json")

    if [ -z "$old_enr" ] || [ "$old_enr" = "null" ]; then
        log_error "Failed to get operator${op_to_replace} ENR from cluster-lock"
        return 1
    fi
    log_info "  Old operator ENR: ${old_enr:0:50}..."

    # Create new operator directory and generate ENR
    local new_op_idx="new"
    local new_op_dir="$TMP_DIR/operator-replace-new"
    mkdir -p "$new_op_dir/.charon" "$new_op_dir/data/lodestar"

    log_info "  Generating ENR for new operator..."
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$new_op_dir/.charon:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        create enr

    local new_enr
    new_enr=$(docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$new_op_dir/.charon:/opt/charon/.charon" \
        "$CHARON_IMAGE" \
        enr 2>/dev/null)

    if [ -z "$new_enr" ]; then
        log_error "Failed to get ENR for new operator"
        return 1
    fi
    log_info "  New operator ENR: ${new_enr:0:50}..."

    # Set up new operator directory with .env, compose file, and cluster-lock
    cat > "$new_op_dir/.env" <<EOF
NETWORK=hoodi
VC=vc-lodestar
EOF
    cp "$TEST_DIR/docker-compose.e2e.yml" "$new_op_dir/docker-compose.e2e.yml"
    cp "$TMP_DIR/operator0/.charon/cluster-lock.json" "$new_op_dir/.charon/cluster-lock.json"

    local remaining_max=$((op_to_replace - 1))

    local pids=()
    local logs_dir="$TMP_DIR/logs/replace-operator"
    mkdir -p "$logs_dir" "$new_op_dir/output"

    # Run remaining operators (all except the one being replaced)
    for i in $(seq 0 "$remaining_max"); do
        local op_dir="$TMP_DIR/operator${i}"
        (
            WORK_DIR="$op_dir" \
            COMPOSE_FILE="$op_dir/docker-compose.e2e.yml" \
            COMPOSE_PROJECT_NAME="e2e-op${i}" \
                "$REPO_ROOT/scripts/edit/replace-operator/remaining-operator.sh" \
                --old-enr "$old_enr" \
                --new-enr "$new_enr"
        ) < /dev/null > "$logs_dir/operator${i}.log" 2>&1 &
        pids+=($!)
    done

    # New operator also participates in the ceremony
    (
        docker run --rm -i \
            --user "$(id -u):$(id -g)" \
            -v "$new_op_dir/.charon:/opt/charon/.charon" \
            -v "$new_op_dir/output:/opt/charon/output" \
            "$CHARON_IMAGE" \
            alpha edit replace-operator \
            --lock-file=/opt/charon/.charon/cluster-lock.json \
            --output-dir=/opt/charon/output \
            --old-operator-enr="$old_enr" \
            --new-operator-enr="$new_enr"
    ) < /dev/null > "$logs_dir/new-operator-ceremony.log" 2>&1 &
    pids+=($!)

    local all_ok=true
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Process $i failed. Log:"
            local logfile="$logs_dir/operator${i}.log"
            # Last pid is the new operator
            if [ "$i" -eq $((${#pids[@]} - 1)) ]; then
                logfile="$logs_dir/new-operator-ceremony.log"
            fi
            sed 's/\r$//' "$logfile" | while IFS= read -r line; do echo "                $line"; done || true
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Post-ceremony: run new-operator.sh to install the cluster-lock
    local new_lock="$new_op_dir/output/cluster-lock.json"
    if [ ! -f "$new_lock" ]; then
        # Fall back to a remaining operator's output
        new_lock="$TMP_DIR/operator0/.charon/cluster-lock.json"
    fi
    (
        WORK_DIR="$new_op_dir" \
        COMPOSE_FILE="$new_op_dir/docker-compose.e2e.yml" \
        COMPOSE_PROJECT_NAME="e2e-op-replace-new" \
            "$REPO_ROOT/scripts/edit/replace-operator/new-operator.sh" \
            --install-lock "$new_lock"
    ) < /dev/null > "$logs_dir/new-operator-setup.log" 2>&1
    if [ $? -ne 0 ]; then
        log_error "New operator post-ceremony setup failed. Log:"
        sed 's/\r$//' "$logs_dir/new-operator-setup.log" | while IFS= read -r line; do echo "                $line"; done || true
        all_ok=false
    fi

    if [ "$all_ok" = false ]; then
        return 1
    fi

    # Verify: same number of operators, new ENR present, old ENR gone
    local ok=true
    for i in $(seq 0 "$remaining_max"); do
        local op_dir="$TMP_DIR/operator${i}"
        local lock="$op_dir/.charon/cluster-lock.json"

        if [ ! -f "$lock" ]; then
            log_error "Operator $i: cluster-lock.json not found"
            ok=false
            continue
        fi

        local num_ops
        num_ops=$(jq '.cluster_definition.operators | length' "$lock")
        assert_eq "Operator $i has $NUM_OPERATORS operators" "$NUM_OPERATORS" "$num_ops" || ok=false
    done

    # Verify new operator has the cluster-lock installed
    if [ ! -f "$new_op_dir/.charon/cluster-lock.json" ]; then
        log_error "New operator: cluster-lock.json not found"
        ok=false
    else
        local new_num_ops
        new_num_ops=$(jq '.cluster_definition.operators | length' "$new_op_dir/.charon/cluster-lock.json")
        assert_eq "New operator has $NUM_OPERATORS operators" "$NUM_OPERATORS" "$new_num_ops" || ok=false
    fi

    # Verify the old ENR is gone and new ENR is present in the cluster-lock
    local lock="$TMP_DIR/operator0/.charon/cluster-lock.json"
    local has_new_enr
    has_new_enr=$(jq -r --arg enr "$new_enr" \
        '[.cluster_definition.operators[].enr] | map(select(. == $enr)) | length' "$lock")
    assert_eq "New ENR present in cluster-lock" "1" "$has_new_enr" || ok=false

    local has_old_enr
    has_old_enr=$(jq -r --arg enr "$old_enr" \
        '[.cluster_definition.operators[].enr] | map(select(. == $enr)) | length' "$lock")
    assert_eq "Old ENR removed from cluster-lock" "0" "$has_old_enr" || ok=false

    # Clean up replaced operator's compose stack
    stop_operator "$op_to_replace"

    [ "$ok" = true ]
}

# --- Main ---

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     E2E Integration Test for Cluster Edit Scripts              ║"
    echo "║     (Real Docker Compose)                                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    setup_tmp_dir
    create_cluster

    # Start compose stacks and seed ASDB for all operators
    start_all_operators
    seed_all_operators

    # Test 1: add-validators (4 ops in parallel)
    run_test "add-validators" test_add_validators
    restart_and_seed_all

    # Test 2: recreate-private-keys (4 ops in parallel)
    run_test "recreate-private-keys" test_recreate_private_keys
    restart_and_seed_all

    # Test 3: add-operators (+3 new = 7 total)
    run_test "add-operators" test_add_operators
    restart_and_seed_all $((NUM_OPERATORS - 1))

    # Test 4: remove-operators (remove 1, leaving 6)
    run_test "remove-operators" test_remove_operators
    restart_and_seed_all $((NUM_OPERATORS - 1))

    # Test 5: replace-operator (replace last operator with a new one)
    run_test "replace-operator" test_replace_operator

    # Summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Test Summary                                               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Tests run:    $TESTS_RUN"
    printf "  Tests passed: ${GREEN}%s${NC}\n" "$TESTS_PASSED"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf "  Tests failed: ${RED}%s${NC}\n" "$TESTS_FAILED"
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
