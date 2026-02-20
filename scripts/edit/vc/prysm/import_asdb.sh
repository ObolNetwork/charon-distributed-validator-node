#!/usr/bin/env bash

# Script to import Prysm validator anti-slashing database from EIP-3076 format.
#
# This script is run by continuing operators after the replace-operator ceremony
# and anti-slashing database update. It imports the updated slashing protection
# database back into the vc-prysm container.
#
# Usage: import_asdb.sh [--input-file <path>] [--data-dir <path>]
#
# Options:
#   --input-file    Path to updated slashing protection JSON (default: ./asdb-export/slashing-protection.json)
#   --data-dir      Path to Prysm data directory (default: ./data/prysm)
#
# Requirements:
#   - .env file must exist with NETWORK variable set
#   - vc-prysm container must be STOPPED before import
#   - docker and docker compose must be available
#   - Input file must be valid EIP-3076 JSON

set -euo pipefail

# Default values
INPUT_FILE="./asdb-export/slashing-protection.json"
DATA_DIR="./data/prysm"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --input-file)
            INPUT_FILE="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            echo "Usage: $0 [--input-file <path>] [--data-dir <path>]" >&2
            exit 1
            ;;
    esac
done

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found in current directory" >&2
    echo "Please ensure you are running this script from the repository root" >&2
    exit 1
fi

# Preserve COMPOSE_FILE and COMPOSE_PROJECT_NAME if already set (e.g., by test scripts)
SAVED_COMPOSE_FILE="${COMPOSE_FILE:-}"
SAVED_COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"

# Source .env to get NETWORK
source .env

# Restore COMPOSE_FILE and COMPOSE_PROJECT_NAME if they were set before sourcing .env
if [ -n "$SAVED_COMPOSE_FILE" ]; then
    export COMPOSE_FILE="$SAVED_COMPOSE_FILE"
fi
if [ -n "$SAVED_COMPOSE_PROJECT_NAME" ]; then
    export COMPOSE_PROJECT_NAME="$SAVED_COMPOSE_PROJECT_NAME"
fi

# Check if NETWORK is set
if [ -z "${NETWORK:-}" ]; then
    echo "Error: NETWORK variable not set in .env file" >&2
    echo "Please set NETWORK (e.g., mainnet, hoodi, sepolia) in your .env file" >&2
    exit 1
fi

echo "Importing anti-slashing database for Prysm validator client"
echo "Network: $NETWORK"
echo "Data directory: $DATA_DIR"
echo "Input file: $INPUT_FILE"
echo ""

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Validate input file is valid JSON
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
    echo "Error: Input file is not valid JSON: $INPUT_FILE" >&2
    exit 1
fi

# Make INPUT_FILE absolute for docker bind mount
if [[ "$INPUT_FILE" != /* ]]; then
    INPUT_FILE="$(pwd)/$INPUT_FILE"
fi

# Check if vc-prysm container is running (it should be stopped)
if docker compose ps vc-prysm 2>/dev/null | grep -q Up; then
    echo "Error: vc-prysm container is still running" >&2
    echo "Please stop the validator client before importing:" >&2
    echo "  docker compose stop vc-prysm" >&2
    echo "" >&2
    echo "Importing while the container is running may cause database corruption." >&2
    exit 1
fi

echo "Importing slashing protection data into vc-prysm container..."

# Import slashing protection data using a temporary container based on the vc-prysm service.
# The input file is bind-mounted into the container at /tmp/slashing_protection.json (read-only).
# We MUST override the entrypoint because the default run.sh ignores arguments.
# Prysm expects the file to be named slashing_protection.json
if ! docker compose run --rm -T \
    --entrypoint /app/cmd/validator/validator \
    -v "$INPUT_FILE":/tmp/slashing_protection.json:ro \
    vc-prysm slashing-protection-history import \
    --accept-terms-of-use \
    --datadir=/data/vc \
    --slashing-protection-json-file=/tmp/slashing_protection.json \
    --$NETWORK; then
    echo "Error: Failed to import slashing protection into vc-prysm container" >&2
    exit 1
fi

echo ""
echo "✓ Successfully imported anti-slashing database"
echo ""
echo "You can now restart the validator client:"
echo "  docker compose up -d vc-prysm"
