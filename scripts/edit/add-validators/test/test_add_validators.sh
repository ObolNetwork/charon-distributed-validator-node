#!/usr/bin/env bash

# Integration test for add-validators.sh script
#
# This test validates:
# - Argument parsing and validation
# - Prerequisite checks (.env, .charon/, cluster-lock)
# - Dry-run output for all workflow steps
# - Error messages for missing inputs
#
# No actual Docker containers are run - all Docker commands are mocked.
#
# Usage: ./scripts/edit/add-validators/test/test_add_validators.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Test directories
TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_DATA_DIR="$SCRIPT_DIR/data"

# Script under test
ADD_VALIDATORS_SCRIPT="$REPO_ROOT/scripts/edit/add-validators/add-validators.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

# Create mock docker script that logs calls and returns success
setup_mock_docker() {
    local mock_bin_dir="$TEST_DATA_DIR/mock-bin"
    mkdir -p "$mock_bin_dir"
    
    # Create mock docker command
    cat > "$mock_bin_dir/docker" << 'MOCK_DOCKER'
#!/usr/bin/env bash
# Mock docker for testing - logs all calls
echo "[MOCK-DOCKER] $*" >> "${MOCK_DOCKER_LOG:-/dev/null}"

# Handle specific commands
case "$*" in
    "info")
        echo "Mock Docker info"
        exit 0
        ;;
    "compose"*"ps"*"charon"*)
        # Simulate charon is running
        echo "charon   Up"
        exit 0
        ;;
    "compose"*"stop"*)
        echo "[MOCK] Stopping containers"
        exit 0
        ;;
    "compose"*"up"*)
        echo "[MOCK] Starting containers"
        exit 0
        ;;
    *"charon"*"add-validators"*)
        echo "[MOCK] Running add-validators ceremony"
        exit 0
        ;;
    *)
        echo "[MOCK] Unhandled docker command: $*"
        exit 0
        ;;
esac
MOCK_DOCKER
    chmod +x "$mock_bin_dir/docker"
    
    # Export PATH with mock first
    export PATH="$mock_bin_dir:$PATH"
    export MOCK_DOCKER_LOG="$TEST_DATA_DIR/docker-calls.log"
}

# Setup test working directory with fixtures
# Note: Scripts always cd to REPO_ROOT, so we must put test fixtures there
# We backup any existing files and restore them on cleanup
setup_test_env() {
    rm -rf "$TEST_DATA_DIR"
    mkdir -p "$TEST_DATA_DIR/backup"
    
    # Backup existing files in REPO_ROOT if they exist
    if [ -f "$REPO_ROOT/.env" ]; then
        cp "$REPO_ROOT/.env" "$TEST_DATA_DIR/backup/.env.bak"
    fi
    if [ -d "$REPO_ROOT/.charon" ]; then
        # Only backup key files, not the whole directory
        mkdir -p "$TEST_DATA_DIR/backup/.charon"
        [ -f "$REPO_ROOT/.charon/cluster-lock.json" ] && \
            cp "$REPO_ROOT/.charon/cluster-lock.json" "$TEST_DATA_DIR/backup/.charon/"
        [ -f "$REPO_ROOT/.charon/charon-enr-private-key" ] && \
            cp "$REPO_ROOT/.charon/charon-enr-private-key" "$TEST_DATA_DIR/backup/.charon/"
    fi
    
    # Install test fixtures to REPO_ROOT
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    mkdir -p "$REPO_ROOT/.charon"
    cp "$TEST_FIXTURES_DIR/.charon/cluster-lock.json" "$REPO_ROOT/.charon/"
    cp "$TEST_FIXTURES_DIR/.charon/charon-enr-private-key" "$REPO_ROOT/.charon/"
    
    # Create required directories
    mkdir -p "$REPO_ROOT/backups"
    
    # Setup mock docker
    setup_mock_docker
}

restore_repo_state() {
    # Restore backed up files
    if [ -f "$TEST_DATA_DIR/backup/.env.bak" ]; then
        cp "$TEST_DATA_DIR/backup/.env.bak" "$REPO_ROOT/.env"
    else
        rm -f "$REPO_ROOT/.env"
    fi
    
    if [ -d "$TEST_DATA_DIR/backup/.charon" ]; then
        [ -f "$TEST_DATA_DIR/backup/.charon/cluster-lock.json" ] && \
            cp "$TEST_DATA_DIR/backup/.charon/cluster-lock.json" "$REPO_ROOT/.charon/"
        [ -f "$TEST_DATA_DIR/backup/.charon/charon-enr-private-key" ] && \
            cp "$TEST_DATA_DIR/backup/.charon/charon-enr-private-key" "$REPO_ROOT/.charon/"
    fi
}

cleanup() {
    log_info "Cleaning up and restoring original state..."
    restore_repo_state
}

trap cleanup EXIT

# Test assertion helpers
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [ "$actual" -eq "$expected" ]; then
        return 0
    else
        log_error "Expected exit code $expected, got $actual in $test_name"
        return 1
    fi
}

assert_output_contains() {
    local pattern="$1"
    local output="$2"
    local test_name="$3"
    
    if echo "$output" | grep -q -F -- "$pattern"; then
        return 0
    else
        log_error "Expected output to contain '$pattern' in $test_name"
        echo "Actual output:"
        echo "$output" | head -20
        return 1
    fi
}

assert_output_not_contains() {
    local pattern="$1"
    local output="$2"
    local test_name="$3"
    
    if echo "$output" | grep -q "$pattern"; then
        log_error "Expected output NOT to contain '$pattern' in $test_name"
        return 1
    else
        return 0
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: $test_name"
    
    if $test_func; then
        echo -e "  ${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗ FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================================================
# ADD-VALIDATORS.SH TESTS
# ============================================================================

test_help() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" --help 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_help" && \
    assert_output_contains "Usage:" "$output" "test_help" && \
    assert_output_contains "--num-validators" "$output" "test_help" && \
    assert_output_contains "--withdrawal-addresses" "$output" "test_help" && \
    assert_output_contains "--dry-run" "$output" "test_help"
}

test_missing_num_validators() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_missing_num_validators" && \
    assert_output_contains "Missing required argument: --num-validators" "$output" "test_missing_num_validators"
}

test_invalid_num_validators() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators abc 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_invalid_num_validators" && \
    assert_output_contains "must be a positive integer" "$output" "test_invalid_num_validators"
}

test_invalid_num_validators_zero() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 0 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_invalid_num_validators_zero" && \
    assert_output_contains "must be a positive integer" "$output" "test_invalid_num_validators_zero"
}

test_missing_env() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/.env"
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 2>&1) || exit_code=$?
    
    # Restore .env for other tests
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_missing_env" && \
    assert_output_contains ".env file not found" "$output" "test_missing_env"
}

test_missing_network() {
    local output
    local exit_code=0
    
    echo "VC=vc-lodestar" > "$REPO_ROOT/.env"  # Missing NETWORK
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 2>&1) || exit_code=$?
    
    # Restore .env
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_missing_network" && \
    assert_output_contains "NETWORK variable not set" "$output" "test_missing_network"
}

test_missing_vc() {
    local output
    local exit_code=0
    
    echo "NETWORK=hoodi" > "$REPO_ROOT/.env"  # Missing VC
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 2>&1) || exit_code=$?
    
    # Restore .env
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_missing_vc" && \
    assert_output_contains "VC variable not set" "$output" "test_missing_vc"
}

test_missing_charon_dir() {
    local output
    local exit_code=0
    
    mv "$REPO_ROOT/.charon" "$REPO_ROOT/.charon.test.bak"
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 2>&1) || exit_code=$?
    
    # Restore .charon
    mv "$REPO_ROOT/.charon.test.bak" "$REPO_ROOT/.charon"
    
    assert_exit_code 1 "$exit_code" "test_missing_charon_dir" && \
    assert_output_contains ".charon directory not found" "$output" "test_missing_charon_dir"
}

test_missing_cluster_lock() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/.charon/cluster-lock.json"
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 2>&1) || exit_code=$?
    
    # Restore cluster-lock
    cp "$TEST_FIXTURES_DIR/.charon/cluster-lock.json" "$REPO_ROOT/.charon/"
    
    assert_exit_code 1 "$exit_code" "test_missing_cluster_lock" && \
    assert_output_contains "cluster-lock.json not found" "$output" "test_missing_cluster_lock"
}

test_dry_run_basic() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_dry_run_basic" && \
    assert_output_contains "DRY-RUN MODE" "$output" "test_dry_run_basic" && \
    assert_output_contains "Validators to add: 5" "$output" "test_dry_run_basic"
}

test_dry_run_with_addresses() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" \
        --num-validators 10 \
        --withdrawal-addresses 0x1234567890abcdef1234567890abcdef12345678 \
        --fee-recipient-addresses 0xabcdef1234567890abcdef1234567890abcdef12 \
        --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_dry_run_with_addresses" && \
    assert_output_contains "Withdrawal addresses:" "$output" "test_dry_run_with_addresses" && \
    assert_output_contains "Fee recipient addresses:" "$output" "test_dry_run_with_addresses"
}

test_dry_run_unverified() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" \
        --num-validators 5 \
        --unverified \
        --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_dry_run_unverified" && \
    assert_output_contains "UNVERIFIED" "$output" "test_dry_run_unverified"
}

test_dry_run_workflow() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_dry_run_workflow" && \
    assert_output_contains "Running add-validators ceremony" "$output" "test_dry_run_workflow" && \
    assert_output_contains "charon alpha edit add-validators" "$output" "test_dry_run_workflow" && \
    assert_output_contains "Stopping containers" "$output" "test_dry_run_workflow" && \
    assert_output_contains "Backing up" "$output" "test_dry_run_workflow" && \
    assert_output_contains "Restarting containers" "$output" "test_dry_run_workflow"
}

test_unknown_argument() {
    local output
    local exit_code=0
    
    output=$("$ADD_VALIDATORS_SCRIPT" --num-validators 5 --invalid-flag 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_unknown_argument" && \
    assert_output_contains "Unknown argument" "$output" "test_unknown_argument"
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Add-Validators Script - Integration Tests                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Setup test environment
    log_info "Setting up test environment..."
    setup_test_env
    
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo " ADD-VALIDATORS.SH TESTS"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    
    run_test "add-validators: --help shows usage" test_help
    run_test "add-validators: error when --num-validators missing" test_missing_num_validators
    run_test "add-validators: error when --num-validators invalid" test_invalid_num_validators
    run_test "add-validators: error when --num-validators is zero" test_invalid_num_validators_zero
    run_test "add-validators: error when .env missing" test_missing_env
    run_test "add-validators: error when NETWORK missing" test_missing_network
    run_test "add-validators: error when VC missing" test_missing_vc
    run_test "add-validators: error when .charon dir missing" test_missing_charon_dir
    run_test "add-validators: error when cluster-lock missing" test_missing_cluster_lock
    run_test "add-validators: dry-run basic" test_dry_run_basic
    run_test "add-validators: dry-run with addresses" test_dry_run_with_addresses
    run_test "add-validators: dry-run with --unverified" test_dry_run_unverified
    run_test "add-validators: dry-run full workflow" test_dry_run_workflow
    run_test "add-validators: error for unknown argument" test_unknown_argument
    
    echo ""
    echo "═════════════════════════════════════════════════════════════════"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All $TESTS_PASSED tests passed!${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}$TESTS_FAILED of $TESTS_RUN tests failed${NC}"
        echo ""
        exit 1
    fi
}

main "$@"
