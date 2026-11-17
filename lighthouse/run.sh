#!/bin/bash

# The vc-bundle service renders Lighthouse's keystores, validator and builder definitions from .charon before this
# starts, in Lighthouse's own layout: a directory per validator with its keystore, the passwords apart.
CHARON_BUNDLE_DIR="/opt/charon/node/vc-bundle"
CHARON_KEYS_DIR="${CHARON_BUNDLE_DIR}/validators"
CHARON_SECRETS_DIR="${CHARON_BUNDLE_DIR}/secrets"
# The validator definitions name the keystores by their path here: --lighthouse-dir in vc-bundle/run.sh.
VC_DATA_DIR="/opt/data"
VC_KEYS_DIR="${VC_DATA_DIR}/validators"
VC_SECRETS_DIR="${VC_DATA_DIR}/secrets"

# Replace the keystores and definitions on every start, but keep the slashing protection DB
# (validators/slashing_protection.sqlite). validator_keys is where earlier versions copied the keystores.
rm -rf "${VC_DATA_DIR}/validator_keys" "${VC_SECRETS_DIR}" "${VC_KEYS_DIR}"/0x*
mkdir -p "${VC_KEYS_DIR}"

# Copy validator keys to VC directory
echo "Importing validator keys..."
cp -r "${CHARON_SECRETS_DIR}" "${VC_SECRETS_DIR}"
cp -r "${CHARON_KEYS_DIR}"/0x* "${VC_KEYS_DIR}/"
echo "Imported $(ls -d "${VC_KEYS_DIR}"/0x* | wc -l) keystores"

# Copy proposer preferences config to VC directory
echo "Importing proposer preferences config..."
cp "${CHARON_KEYS_DIR}/validator_definitions.yml" "${VC_KEYS_DIR}/"
echo "Imported proposer preferences config to ${VC_KEYS_DIR}/validator_definitions.yml"

# Copy builder preferences config to VC directory
echo "Importing builder preferences config..."
cp "${CHARON_KEYS_DIR}/builder_definitions.yml" "${VC_KEYS_DIR}/"
echo "Imported builder preferences config to ${VC_KEYS_DIR}/builder_definitions.yml"

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
