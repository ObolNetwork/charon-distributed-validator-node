#!/bin/bash

# The vc-bundle service renders Lighthouse's validator and builder definitions from .charon before this starts.
CHARON_BUNDLE_DIR="/opt/charon/node/vc-bundle"
CHARON_KEYS_DIR="/opt/charon/node/validator_keys"
VC_DATA_DIR="/opt/data"
# The validator definitions point at the keystores by their path here: --validator-keys-dir in vc-bundle/run.sh.
VC_KEYS_DIR="${VC_DATA_DIR}/validator_keys"
# Lighthouse reads its validator (proposer preferences) and builder definitions from here.
VC_DEFINITIONS_DIR="${VC_DATA_DIR}/validators"

# Copy validator keys to VC directory
echo "Importing validator keys..."
rm -rf "${VC_KEYS_DIR}"
cp -r "${CHARON_KEYS_DIR}" "${VC_KEYS_DIR}"
echo "Imported $(ls "${VC_KEYS_DIR}"/keystore-*.json | wc -l) keystores"

mkdir -p "${VC_DEFINITIONS_DIR}"

# Copy proposer preferences config to VC directory
echo "Importing proposer preferences config..."
cp "${CHARON_BUNDLE_DIR}/validators/validator_definitions.yml" "${VC_DEFINITIONS_DIR}/"
echo "Imported proposer preferences config to ${VC_DEFINITIONS_DIR}/validator_definitions.yml"

# Copy builder preferences config to VC directory
echo "Importing builder preferences config..."
cp "${CHARON_BUNDLE_DIR}/validators/builder_definitions.yml" "${VC_DEFINITIONS_DIR}/"
echo "Imported builder preferences config to ${VC_DEFINITIONS_DIR}/builder_definitions.yml"

exec lighthouse validator_client \
    --network "${NETWORK}" \
    --datadir "${VC_DATA_DIR}" \
    --beacon-nodes "${BEACON_NODE_ADDRESS}" \
    --disable-auto-discover \
    --init-slashing-protection \
    --metrics \
    --metrics-address 0.0.0.0 \
    --metrics-port 5064 \
    --distributed
