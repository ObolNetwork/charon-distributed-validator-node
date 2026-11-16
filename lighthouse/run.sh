#!/bin/bash

# The vc-bundle service renders Lighthouse's validator and builder definitions and flags from .charon before this
# starts. The definitions point at the keystores in /opt/charon/validator_keys, mounted here at the same path.
BUNDLE_DIR="/opt/charon/node/vc-bundle"
VALIDATORS_DIR="/opt/data/validators"

mkdir -p "${VALIDATORS_DIR}"
cp "${BUNDLE_DIR}/validators/validator_definitions.yml" "${VALIDATORS_DIR}/"

# Without builders in the proposer config the bundle holds no builder definitions: remove a stale one.
if [[ -f "${BUNDLE_DIR}/validators/builder_definitions.yml" ]]; then
    cp "${BUNDLE_DIR}/validators/builder_definitions.yml" "${VALIDATORS_DIR}/"
else
    rm -f "${VALIDATORS_DIR}/builder_definitions.yml"
fi

mapfile -t VC_FLAGS <"${BUNDLE_DIR}/vc-flags.txt"

exec lighthouse validator_client \
    --network "${NETWORK}" \
    --datadir /opt/data \
    --beacon-nodes "${BEACON_NODE_ADDRESS}" \
    --disable-auto-discover \
    --init-slashing-protection \
    --metrics \
    --metrics-address 0.0.0.0 \
    --metrics-port 5064 \
    "${VC_FLAGS[@]}"
