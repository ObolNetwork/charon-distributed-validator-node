#!/usr/bin/env bash

# Script to export validator anti-slashing database to EIP-3076 format.
#
# This script routes to the appropriate VC-specific export script based on the VC environment variable.
#
# Usage: VC=vc-lodestar ./scripts/edit/vc/export_asdb.sh [options]
#
# Environment Variables:
#   VC              Validator client type (e.g., vc-lodestar, vc-teku, vc-prysm, vc-nimbus)
#
# All options are passed through to the VC-specific script.

set -euo pipefail

# Check if VC environment variable is set
if [ -z "${VC:-}" ]; then
    echo "Error: VC environment variable is not set" >&2
    echo "Usage: VC=vc-lodestar $0 [options]" >&2
    echo "" >&2
    echo "Supported VC types:" >&2
    echo "  - vc-lodestar" >&2
    echo "  - vc-teku" >&2
    echo "  - vc-prysm" >&2
    echo "  - vc-nimbus" >&2
    exit 1
fi

# Extract the VC name (remove "vc-" prefix)
VC_NAME="${VC#vc-}"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path to the VC-specific script
VC_SCRIPT="${SCRIPT_DIR}/${VC_NAME}/export_asdb.sh"

# Check if the VC-specific script exists
if [ ! -f "$VC_SCRIPT" ]; then
    echo "Error: Export script for '$VC' not found at: $VC_SCRIPT" >&2
    echo "" >&2
    echo "Available VC types:" >&2
    for dir in "${SCRIPT_DIR}"/*; do
        if [ -d "$dir" ] && [ -f "$dir/export_asdb.sh" ]; then
            basename "$dir"
        fi
    done | sed 's/^/  - vc-/' >&2
    exit 1
fi

# Make sure the VC-specific script is executable
chmod +x "$VC_SCRIPT"

# Run the VC-specific script with all arguments passed through
echo "Running export for $VC..."
exec "$VC_SCRIPT" "$@"
