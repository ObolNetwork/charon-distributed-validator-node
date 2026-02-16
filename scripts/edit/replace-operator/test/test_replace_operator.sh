#!/usr/bin/env bash

# Integration test for replace-operator scripts (new-operator.sh & remaining-operator.sh)
#
# This test validates:
# - Argument parsing and validation
# - Prerequisite checks (.env, .charon/, cluster-lock, ENR key)
# - Dry-run output for all workflow steps
# - Error messages for missing inputs
#
# No actual Docker containers or ceremonies are run - all Docker commands are mocked.
#
# Usage: ./scripts/edit/replace-operator/test/test_replace_operator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Test directories
TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_DATA_DIR="$SCRIPT_DIR/data"

# Scripts under test
NEW_OPERATOR_SCRIPT="$REPO_ROOT/scripts/edit/replace-operator/new-operator.sh"
REMAINING_OPERATOR_SCRIPT="$REPO_ROOT/scripts/edit/replace-operator/remaining-operator.sh"

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
    "compose"*"ps"*)
        # Simulate container not running (for remaining-operator checks)
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
    *"charon"*"enr"*)
        # Return a mock ENR
        echo "enr:-HW4QMockENRForTesting12345"
        exit 0
        ;;
    *"charon"*"create enr"*)
        echo "[MOCK] Creating ENR"
        exit 0
        ;;
    *"charon"*"edit replace-operator"*)
        echo "[MOCK] Running replace-operator ceremony"
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
    mkdir -p "$REPO_ROOT/output"
    mkdir -p "$REPO_ROOT/asdb-export"
    
    # Copy sample ASDB for remaining-operator tests
    cp "$TEST_FIXTURES_DIR/sample-asdb.json" "$REPO_ROOT/asdb-export/slashing-protection.json"
    
    # Copy new cluster-lock fixture to output
    cp "$TEST_FIXTURES_DIR/new-cluster-lock.json" "$REPO_ROOT/output/cluster-lock.json"
    
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
    
    # Clean up test artifacts
    rm -f "$REPO_ROOT/asdb-export/slashing-protection.json"
    rm -f "$REPO_ROOT/output/cluster-lock.json"
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
# NEW-OPERATOR.SH TESTS
# ============================================================================

test_new_help() {
    local output
    local exit_code=0
    
    output=$("$NEW_OPERATOR_SCRIPT" --help 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_new_help" && \
    assert_output_contains "Usage:" "$output" "test_new_help" && \
    assert_output_contains "--cluster-lock" "$output" "test_new_help" && \
    assert_output_contains "--generate-enr" "$output" "test_new_help" && \
    assert_output_contains "--dry-run" "$output" "test_new_help"
}

test_new_missing_env() {
    local output
    local exit_code=0
    
    # Remove .env from REPO_ROOT
    rm -f "$REPO_ROOT/.env"
    
    output=$("$NEW_OPERATOR_SCRIPT" 2>&1) || exit_code=$?
    
    # Restore .env for other tests
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_new_missing_env" && \
    assert_output_contains ".env file not found" "$output" "test_new_missing_env"
}

test_new_missing_network() {
    local output
    local exit_code=0
    
    echo "VC=vc-lodestar" > "$REPO_ROOT/.env"  # Missing NETWORK
    
    output=$("$NEW_OPERATOR_SCRIPT" 2>&1) || exit_code=$?
    
    # Restore .env
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_new_missing_network" && \
    assert_output_contains "NETWORK variable not set" "$output" "test_new_missing_network"
}

test_new_missing_vc() {
    local output
    local exit_code=0
    
    echo "NETWORK=hoodi" > "$REPO_ROOT/.env"  # Missing VC
    
    output=$("$NEW_OPERATOR_SCRIPT" 2>&1) || exit_code=$?
    
    # Restore .env
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_new_missing_vc" && \
    assert_output_contains "VC variable not set" "$output" "test_new_missing_vc"
}

test_new_missing_charon_dir() {
    local output
    local exit_code=0
    
    # Temporarily rename .charon
    mv "$REPO_ROOT/.charon" "$REPO_ROOT/.charon.test.bak"
    
    output=$("$NEW_OPERATOR_SCRIPT" 2>&1) || exit_code=$?
    
    # Restore .charon
    mv "$REPO_ROOT/.charon.test.bak" "$REPO_ROOT/.charon"
    
    assert_exit_code 1 "$exit_code" "test_new_missing_charon_dir" && \
    assert_output_contains ".charon directory not found" "$output" "test_new_missing_charon_dir"
}

test_new_missing_enr_key() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/.charon/charon-enr-private-key"
    
    output=$("$NEW_OPERATOR_SCRIPT" 2>&1) || exit_code=$?
    
    # Restore ENR key
    cp "$TEST_FIXTURES_DIR/.charon/charon-enr-private-key" "$REPO_ROOT/.charon/"
    
    assert_exit_code 1 "$exit_code" "test_new_missing_enr_key" && \
    assert_output_contains "charon-enr-private-key not found" "$output" "test_new_missing_enr_key"
}

test_new_invalid_cluster_lock_path() {
    local output
    local exit_code=0
    
    output=$("$NEW_OPERATOR_SCRIPT" --cluster-lock /nonexistent/path.json 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_new_invalid_cluster_lock_path" && \
    assert_output_contains "Cluster-lock file not found" "$output" "test_new_invalid_cluster_lock_path"
}

test_new_dry_run_generate_enr() {
    local output
    local exit_code=0
    
    output=$("$NEW_OPERATOR_SCRIPT" --generate-enr --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_new_dry_run_generate_enr" && \
    assert_output_contains "DRY-RUN MODE" "$output" "test_new_dry_run_generate_enr" && \
    assert_output_contains "Generating ENR" "$output" "test_new_dry_run_generate_enr"
}

test_new_dry_run_join_cluster() {
    local output
    local exit_code=0
    
    output=$("$NEW_OPERATOR_SCRIPT" --cluster-lock "$TEST_FIXTURES_DIR/new-cluster-lock.json" --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_new_dry_run_join_cluster" && \
    assert_output_contains "DRY-RUN MODE" "$output" "test_new_dry_run_join_cluster" && \
    assert_output_contains "Stopping" "$output" "test_new_dry_run_join_cluster" && \
    assert_output_contains "Installing new cluster-lock" "$output" "test_new_dry_run_join_cluster" && \
    assert_output_contains "Starting containers" "$output" "test_new_dry_run_join_cluster"
}

test_new_unknown_argument() {
    local output
    local exit_code=0
    
    output=$("$NEW_OPERATOR_SCRIPT" --invalid-flag 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_new_unknown_argument" && \
    assert_output_contains "Unknown argument" "$output" "test_new_unknown_argument"
}

# ============================================================================
# REMAINING-OPERATOR.SH TESTS
# ============================================================================

test_remaining_help() {
    local output
    local exit_code=0
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --help 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_remaining_help" && \
    assert_output_contains "Usage:" "$output" "test_remaining_help" && \
    assert_output_contains "--new-enr" "$output" "test_remaining_help" && \
    assert_output_contains "--operator-index" "$output" "test_remaining_help" && \
    assert_output_contains "--skip-export" "$output" "test_remaining_help"
}

test_remaining_missing_new_enr() {
    local output
    local exit_code=0
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --operator-index 0 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_remaining_missing_new_enr" && \
    assert_output_contains "Missing required argument: --new-enr" "$output" "test_remaining_missing_new_enr"
}

test_remaining_missing_operator_index() {
    local output
    local exit_code=0
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --new-enr "enr:-test123" 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_remaining_missing_operator_index" && \
    assert_output_contains "Missing required argument: --operator-index" "$output" "test_remaining_missing_operator_index"
}

test_remaining_missing_env() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/.env"
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --new-enr "enr:-test" --operator-index 0 2>&1) || exit_code=$?
    
    # Restore .env
    cp "$TEST_FIXTURES_DIR/.env.test" "$REPO_ROOT/.env"
    
    assert_exit_code 1 "$exit_code" "test_remaining_missing_env" && \
    assert_output_contains ".env file not found" "$output" "test_remaining_missing_env"
}

test_remaining_missing_charon_dir() {
    local output
    local exit_code=0
    
    mv "$REPO_ROOT/.charon" "$REPO_ROOT/.charon.test.bak"
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --new-enr "enr:-test" --operator-index 0 2>&1) || exit_code=$?
    
    # Restore .charon
    mv "$REPO_ROOT/.charon.test.bak" "$REPO_ROOT/.charon"
    
    assert_exit_code 1 "$exit_code" "test_remaining_missing_charon_dir" && \
    assert_output_contains ".charon directory not found" "$output" "test_remaining_missing_charon_dir"
}

test_remaining_missing_cluster_lock() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/.charon/cluster-lock.json"
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --new-enr "enr:-test" --operator-index 0 2>&1) || exit_code=$?
    
    # Restore cluster-lock
    cp "$TEST_FIXTURES_DIR/.charon/cluster-lock.json" "$REPO_ROOT/.charon/"
    
    assert_exit_code 1 "$exit_code" "test_remaining_missing_cluster_lock" && \
    assert_output_contains "cluster-lock.json not found" "$output" "test_remaining_missing_cluster_lock"
}

test_remaining_missing_enr_key() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/.charon/charon-enr-private-key"
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --new-enr "enr:-test" --operator-index 0 2>&1) || exit_code=$?
    
    # Restore ENR key
    cp "$TEST_FIXTURES_DIR/.charon/charon-enr-private-key" "$REPO_ROOT/.charon/"
    
    assert_exit_code 1 "$exit_code" "test_remaining_missing_enr_key" && \
    assert_output_contains "charon-enr-private-key not found" "$output" "test_remaining_missing_enr_key"
}

test_remaining_dry_run_full_workflow() {
    local output
    local exit_code=0
    
    # Use --skip-export to avoid Docker dependencies
    output=$("$REMAINING_OPERATOR_SCRIPT" \
        --new-enr "enr:-HW4QTestNewOperator123456789" \
        --operator-index 0 \
        --skip-export \
        --dry-run 2>&1) || exit_code=$?
    
    assert_exit_code 0 "$exit_code" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "DRY-RUN MODE" "$output" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "charon edit replace-operator" "$output" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "Updating anti-slashing database pubkeys" "$output" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "Stopping" "$output" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "Backing up" "$output" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "Importing" "$output" "test_remaining_dry_run_full_workflow" && \
    assert_output_contains "Restarting" "$output" "test_remaining_dry_run_full_workflow"
}

test_remaining_skip_export_missing_asdb() {
    local output
    local exit_code=0
    
    rm -f "$REPO_ROOT/asdb-export/slashing-protection.json"
    
    output=$("$REMAINING_OPERATOR_SCRIPT" \
        --new-enr "enr:-test" \
        --operator-index 0 \
        --skip-export \
        --dry-run 2>&1) || exit_code=$?
    
    # Restore ASDB
    cp "$TEST_FIXTURES_DIR/sample-asdb.json" "$REPO_ROOT/asdb-export/slashing-protection.json"
    
    assert_exit_code 1 "$exit_code" "test_remaining_skip_export_missing_asdb" && \
    assert_output_contains "Cannot skip export" "$output" "test_remaining_skip_export_missing_asdb"
}

test_remaining_unknown_argument() {
    local output
    local exit_code=0
    
    output=$("$REMAINING_OPERATOR_SCRIPT" --invalid-flag 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "test_remaining_unknown_argument" && \
    assert_output_contains "Unknown argument" "$output" "test_remaining_unknown_argument"
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Replace-Operator Scripts - Integration Tests               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Setup test environment
    log_info "Setting up test environment..."
    setup_test_env
    
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo " NEW-OPERATOR.SH TESTS"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    
    run_test "new-operator: --help shows usage" test_new_help
    run_test "new-operator: error when .env missing" test_new_missing_env
    run_test "new-operator: error when NETWORK missing" test_new_missing_network
    run_test "new-operator: error when VC missing" test_new_missing_vc
    run_test "new-operator: error when .charon dir missing" test_new_missing_charon_dir
    run_test "new-operator: error when ENR key missing" test_new_missing_enr_key
    run_test "new-operator: error for invalid cluster-lock path" test_new_invalid_cluster_lock_path
    run_test "new-operator: dry-run generate ENR" test_new_dry_run_generate_enr
    run_test "new-operator: dry-run join cluster" test_new_dry_run_join_cluster
    run_test "new-operator: error for unknown argument" test_new_unknown_argument
    
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo " REMAINING-OPERATOR.SH TESTS"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    
    run_test "remaining-operator: --help shows usage" test_remaining_help
    run_test "remaining-operator: error when --new-enr missing" test_remaining_missing_new_enr
    run_test "remaining-operator: error when --operator-index missing" test_remaining_missing_operator_index
    run_test "remaining-operator: error when .env missing" test_remaining_missing_env
    run_test "remaining-operator: error when .charon dir missing" test_remaining_missing_charon_dir
    run_test "remaining-operator: error when cluster-lock missing" test_remaining_missing_cluster_lock
    run_test "remaining-operator: error when ENR key missing" test_remaining_missing_enr_key
    run_test "remaining-operator: dry-run full workflow" test_remaining_dry_run_full_workflow
    run_test "remaining-operator: skip-export needs existing ASDB" test_remaining_skip_export_missing_asdb
    run_test "remaining-operator: error for unknown argument" test_remaining_unknown_argument
    
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
