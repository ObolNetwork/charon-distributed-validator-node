#!/usr/bin/env bash

# Script to import Teku validator anti-slashing database from EIP-3076 format.
#
# This script is run by continuing operators after the replace-operator ceremony
# and anti-slashing database update. It imports the updated slashing protection
# database back into the vc-teku container.
#
# Usage: import_asdb.sh [--input-file <path>] [--data-dir <path>]
#
# Options:
#   --input-file    Path to updated slashing protection JSON (default: ./asdb-export/slashing-protection.json)
#   --data-dir      Path to Teku data directory (default: ./data/vc-teku)
#
# Requirements:
#   - .env file must exist with NETWORK variable set
#   - vc-teku container must be STOPPED before import
#   - docker and docker compose must be available
#   - Input file must be valid EIP-3076 JSON

set -euo pipefail

# Default values
INPUT_FILE="./asdb-export/slashing-protection.json"
DATA_DIR="./data/vc-teku"

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

# Preserve COMPOSE_FILE if already set (e.g., by test scripts)
SAVED_COMPOSE_FILE="${COMPOSE_FILE:-}"

# Source .env to get NETWORK
source .env

# Restore COMPOSE_FILE if it was set before sourcing .env
if [ -n "$SAVED_COMPOSE_FILE" ]; then
    export COMPOSE_FILE="$SAVED_COMPOSE_FILE"
fi

# Check if NETWORK is set
if [ -z "${NETWORK:-}" ]; then
    echo "Error: NETWORK variable not set in .env file" >&2
    echo "Please set NETWORK (e.g., mainnet, hoodi, sepolia) in your .env file" >&2
    exit 1
fi

echo "Importing anti-slashing database for Teku validator client"
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

# Check if vc-teku container is running (it should be stopped)
if docker compose ps vc-teku 2>/dev/null | grep -q Up; then
    echo "Error: vc-teku container is still running" >&2
    echo "Please stop the validator client before importing:" >&2
    echo "  docker compose stop vc-teku" >&2
    echo "" >&2
    echo "Importing while the container is running may cause database corruption." >&2
    exit 1
fi

echo "Importing slashing protection data into vc-teku container..."

# Import slashing protection data using a temporary container based on the vc-teku service.
# The input file is bind-mounted into the container at /tmp/import.json (read-only).
# We override the command to run the import instead of the validator client.
if ! docker compose run --rm -T \
    -v "$INPUT_FILE":/tmp/import.json:ro \
    --entrypoint /opt/teku/bin/teku \
    vc-teku slashing-protection import \
    --data-path=/home/data \
    --from=/tmp/import.json; then
    echo "Error: Failed to import slashing protection into vc-teku container" >&2
    exit 1
fi

echo ""
echo "✓ Successfully imported anti-slashing database"
echo ""
echo "You can now restart the validator client:"
echo "  docker compose up -d vc-teku"
