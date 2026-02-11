#!/usr/bin/env bash

# Script to export Teku validator anti-slashing database to EIP-3076 format.
#
# This script is run by continuing operators before the replace-operator ceremony.
# It exports the slashing protection database from the running vc-teku container
# to a JSON file that can be updated and re-imported after the ceremony.
#
# Usage: export_asdb.sh [--data-dir <path>] [--output-file <path>]
#
# Options:
#   --data-dir      Path to Teku data directory (default: ./data/vc-teku)
#   --output-file   Path for exported slashing protection JSON (default: ./asdb-export/slashing-protection.json)
#
# Requirements:
#   - .env file must exist with NETWORK variable set
#   - vc-teku container must be running
#   - docker and docker compose must be available

set -euo pipefail

# Default values
DATA_DIR="./data/vc-teku"
OUTPUT_FILE="./asdb-export/slashing-protection.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            echo "Usage: $0 [--data-dir <path>] [--output-file <path>]" >&2
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

echo "Exporting anti-slashing database for Teku validator client"
echo "Network: $NETWORK"
echo "Data directory: $DATA_DIR"
echo "Output file: $OUTPUT_FILE"
echo ""

# Check if vc-teku container is running
if ! docker compose ps vc-teku | grep -q Up; then
    echo "Error: vc-teku container is not running" >&2
    echo "Please start the validator client before exporting:" >&2
    echo "  docker compose up -d vc-teku" >&2
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

echo "Exporting slashing protection data from vc-teku container..."

# Export slashing protection data from the container
# Teku stores data in /home/data (mapped from ./data/vc-teku)
# The export command writes to a file we specify
if ! docker compose exec -T vc-teku /opt/teku/bin/teku slashing-protection export \
    --data-path=/home/data \
    --to=/tmp/export.json; then
    echo "Error: Failed to export slashing protection from vc-teku container" >&2
    exit 1
fi

echo "Copying exported file from container to host..."

# Copy the exported file from container to host
if ! docker compose cp vc-teku:/tmp/export.json "$OUTPUT_FILE"; then
    echo "Error: Failed to copy exported file from container" >&2
    exit 1
fi

# Validate the exported JSON
if ! jq empty "$OUTPUT_FILE" 2>/dev/null; then
    echo "Error: Exported file is not valid JSON" >&2
    exit 1
fi

echo ""
echo "✓ Successfully exported anti-slashing database"
echo "  Output file: $OUTPUT_FILE"
echo ""
echo "You can now proceed with the replace-operator ceremony."
