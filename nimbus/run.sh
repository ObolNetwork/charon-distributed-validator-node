#!/usr/bin/env bash
# Start the Nimbus validator client. Preserves ./data/vc-nimbus (no wipe on restart).
# Imports keys automatically when ./data/vc-nimbus/validators is empty.

set -euo pipefail

DATA_DIR="/home/user/data"
export DATA_DIR
export VALIDATOR_KEYS_DIR="${VALIDATOR_KEYS_DIR:-/home/validator_keys}"
export NIMBUS_BEACON_NODE="${NIMBUS_BEACON_NODE:-/home/user/bin/nimbus_beacon_node}"

bash /import-keys.sh

if ! find "${DATA_DIR}/validators" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
  echo "Error: key import completed but no validators found in ${DATA_DIR}/validators." >&2
  exit 1
fi

exec /home/user/nimbus_validator_client \
  --data-dir="${DATA_DIR}" \
  --beacon-node="${BEACON_NODE_ADDRESS}" \
  --doppelganger-detection=false \
  --metrics \
  --metrics-address=0.0.0.0 \
  --payload-builder="${BUILDER_API_ENABLED}" \
  --distributed
