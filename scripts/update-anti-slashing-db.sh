#!/usr/bin/env bash

# Script to update EIP-3076 anti-slashing DB by replacing pubkey values
# based on lookup in source and target cluster-lock.json files.
#
# Usage: update-anti-slashing-db.sh <eip3076-file> <source-cluster-lock> <target-cluster-lock>
#
# Arguments:
#   eip3076-file          - Path to EIP-3076 JSON file to update in place
#   source-cluster-lock   - Path to source cluster-lock.json
#   target-cluster-lock   - Path to target cluster-lock.json
#
# The script traverses the EIP-3076 JSON file and finds all "pubkey" values in the
# data array. For each pubkey, it looks up the value in the source cluster-lock.json's
# distributed_validators[].public_shares[] arrays, remembers the indices, and then
# replaces the pubkey with the corresponding value from the target cluster-lock.json
# at the same indices.

set -euo pipefail

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first." >&2
    exit 1
fi

# Validate arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <eip3076-file> <source-cluster-lock> <target-cluster-lock>" >&2
    exit 1
fi

EIP3076_FILE="$1"
SOURCE_LOCK="$2"
TARGET_LOCK="$3"

# Validate files exist
if [ ! -f "$EIP3076_FILE" ]; then
    echo "Error: EIP-3076 file not found: $EIP3076_FILE" >&2
    exit 1
fi

if [ ! -f "$SOURCE_LOCK" ]; then
    echo "Error: Source cluster-lock file not found: $SOURCE_LOCK" >&2
    exit 1
fi

if [ ! -f "$TARGET_LOCK" ]; then
    echo "Error: Target cluster-lock file not found: $TARGET_LOCK" >&2
    exit 1
fi

# Validate all files contain valid JSON
if ! jq empty "$EIP3076_FILE" 2>/dev/null; then
    echo "Error: EIP-3076 file contains invalid JSON: $EIP3076_FILE" >&2
    exit 1
fi

if ! jq empty "$SOURCE_LOCK" 2>/dev/null; then
    echo "Error: Source cluster-lock file contains invalid JSON: $SOURCE_LOCK" >&2
    exit 1
fi

if ! jq empty "$TARGET_LOCK" 2>/dev/null; then
    echo "Error: Target cluster-lock file contains invalid JSON: $TARGET_LOCK" >&2
    exit 1
fi

# Create temporary files for processing
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE" "${TEMP_FILE}.tmp"' EXIT

# Function to find pubkey in cluster-lock and return validator_index,share_index
# Returns empty string if not found
find_pubkey_indices() {
    local pubkey="$1"
    local cluster_lock_file="$2"

    # Search through distributed_validators and public_shares
    jq -r --arg pubkey "$pubkey" '
        .distributed_validators as $validators |
        foreach range(0; $validators | length) as $v_idx (
            null;
            . ;
            $validators[$v_idx].public_shares as $shares |
            foreach range(0; $shares | length) as $s_idx (
                null;
                . ;
                if $shares[$s_idx] == $pubkey then
                    "\($v_idx),\($s_idx)"
                else
                    empty
                end
            )
        ) | select(. != null)
    ' "$cluster_lock_file" | head -n 1
}

# Function to get pubkey from cluster-lock at specific indices
get_pubkey_at_indices() {
    local validator_idx="$1"
    local share_idx="$2"
    local cluster_lock_file="$3"

    jq -r --argjson v_idx "$validator_idx" --argjson s_idx "$share_idx" '
        .distributed_validators[$v_idx].public_shares[$s_idx]
    ' "$cluster_lock_file"
}

echo "Reading EIP-3076 file: $EIP3076_FILE"
echo "Source cluster-lock: $SOURCE_LOCK"
echo "Target cluster-lock: $TARGET_LOCK"
echo ""

# Validate cluster-lock structure
source_validators=$(jq '.distributed_validators | length' "$SOURCE_LOCK")
target_validators=$(jq '.distributed_validators | length' "$TARGET_LOCK")

echo "Source cluster-lock has $source_validators validators"
echo "Target cluster-lock has $target_validators validators"

if [ "$source_validators" -eq 0 ]; then
    echo "Error: Source cluster-lock has no validators" >&2
    exit 1
fi

if [ "$target_validators" -eq 0 ]; then
    echo "Error: Target cluster-lock has no validators" >&2
    exit 1
fi

# Verify that target has at least as many validators as source
if [ "$target_validators" -lt "$source_validators" ]; then
    echo "Error: Target cluster-lock has fewer validators ($target_validators) than source ($source_validators)" >&2
    echo "       This may result in missing pubkey replacements" >&2
    exit 1
fi

echo ""

# Get all unique pubkeys from the data array
# Note: The same pubkey may appear multiple times, so we deduplicate with sort -u
pubkeys=$(jq -r '.data[].pubkey' "$EIP3076_FILE" | sort -u)

if [ -z "$pubkeys" ]; then
    echo "Warning: No pubkeys found in EIP-3076 file" >&2
    exit 0
fi

pubkey_count=$(echo "$pubkeys" | wc -l | tr -d ' ')
echo "Found $pubkey_count unique pubkey(s) to process"
echo ""

# Copy original file to temp file, we'll modify it in place
cp "$EIP3076_FILE" "$TEMP_FILE"

# Process each pubkey
while IFS= read -r old_pubkey; do
    echo "Processing pubkey: $old_pubkey"

    # Find indices in source cluster-lock
    indices=$(find_pubkey_indices "$old_pubkey" "$SOURCE_LOCK")

    if [ -z "$indices" ]; then
        echo "  Error: Pubkey not found in source cluster-lock.json" >&2
        echo "         Cannot proceed without mapping for all pubkeys" >&2
        exit 1
    fi

    # Split indices
    validator_idx=$(echo "$indices" | cut -d',' -f1)
    share_idx=$(echo "$indices" | cut -d',' -f2)

    echo "  Found at distributed_validators[$validator_idx].public_shares[$share_idx]"

    # Verify target has sufficient validators
    target_validator_count=$(jq '.distributed_validators | length' "$TARGET_LOCK")
    if [ "$validator_idx" -ge "$target_validator_count" ]; then
        echo "  Error: Target cluster-lock.json doesn't have validator at index $validator_idx" >&2
        echo "         Target has only $target_validator_count validators" >&2
        exit 1
    fi

    # Verify target validator has sufficient public_shares
    target_share_count=$(jq --argjson v_idx "$validator_idx" '.distributed_validators[$v_idx].public_shares | length' "$TARGET_LOCK")
    if [ "$share_idx" -ge "$target_share_count" ]; then
        echo "  Error: Target cluster-lock.json validator[$validator_idx] doesn't have share at index $share_idx" >&2
        echo "         Target validator has only $target_share_count shares" >&2
        exit 1
    fi

    # Get corresponding pubkey from target cluster-lock
    new_pubkey=$(get_pubkey_at_indices "$validator_idx" "$share_idx" "$TARGET_LOCK")

    if [ -z "$new_pubkey" ] || [ "$new_pubkey" = "null" ]; then
        echo "  Error: Could not find pubkey at same indices in target cluster-lock.json" >&2
        exit 1
    fi

    echo "  Replacing with: $new_pubkey"

    # Replace the pubkey in the JSON data
    # Note: The same pubkey may appear multiple times in the data array (one per validator).
    # This filter will update ALL occurrences of the old pubkey with the new one.
    # We modify the temp file in place using jq's output redirection
    jq --arg old "$old_pubkey" --arg new "$new_pubkey" '
        (.data[] | select(.pubkey == $old) | .pubkey) |= $new
    ' "$TEMP_FILE" > "${TEMP_FILE}.tmp" && mv "${TEMP_FILE}.tmp" "$TEMP_FILE"

    echo "  Done"
    echo ""
done <<< "$pubkeys"

# Validate the output is valid JSON
if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    echo "Error: Generated invalid JSON" >&2
    exit 1
fi

# Replace original file with updated version
cp "$TEMP_FILE" "$EIP3076_FILE"

echo "Successfully updated $EIP3076_FILE"
