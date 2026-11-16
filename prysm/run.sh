#!/usr/bin/env bash

# The vc-bundle service renders Prysm's wallet, proposer settings and flags from .charon before this starts. The
# wallet holds this node's key shares and its password file, so Prysm reads it in place without an import.
BUNDLE_DIR="/opt/charon/node/vc-bundle"

mapfile -t VC_FLAGS <"${BUNDLE_DIR}/vc-flags.txt"

exec /app/cmd/validator/validator --wallet-dir="${BUNDLE_DIR}/prysm-wallet" \
    --accept-terms-of-use=true \
    --datadir="/data/vc" \
    --monitoring-host=0.0.0.0 \
    --beacon-rest-api-provider="${BEACON_NODE_ADDRESS}" \
    --beacon-rpc-provider="${BEACON_NODE_ADDRESS}" \
    --"${NETWORK}" \
    --proposer-settings-file="${BUNDLE_DIR}/prysm-proposer-settings.json" \
    "${VC_FLAGS[@]}"
