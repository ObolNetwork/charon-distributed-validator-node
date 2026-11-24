#!/bin/bash

set -e

# The vc-files service leaves Lighthouse's keystores, validator and builder definitions in .charon/vc-files before
# this starts, in Lighthouse's own layout: a directory per validator with its keystore, the passwords apart.
CHARON_KEYS_DIR="/opt/charon/vc-files/keys"
CHARON_CONFIG_DIR="/opt/charon/vc-files/config"
# The validator definitions name the keystores by their path here: --lighthouse-dir in vc-files/run.sh.
VC_DATA_DIR="/opt/data"
VC_KEYS_DIR="${VC_DATA_DIR}/validators"
VC_SECRETS_DIR="${VC_DATA_DIR}/secrets"

if [ -d "${CHARON_KEYS_DIR}" ]; then
    # Replace the keystores and definitions, but keep the slashing protection DB
    # (validators/slashing_protection.sqlite). validator_keys is where earlier versions copied the keystores.
    rm -rf "${VC_DATA_DIR}/validator_keys" "${VC_SECRETS_DIR}" "${VC_KEYS_DIR}"/0x*
    mkdir -p "${VC_KEYS_DIR}"

    # Copy validator keys to VC directory
    echo "Importing validator keys..."
    cp -r "${CHARON_KEYS_DIR}/secrets" "${VC_SECRETS_DIR}"
    cp -r "${CHARON_KEYS_DIR}/validators"/0x* "${VC_KEYS_DIR}/"
    echo "Imported $(ls -d "${VC_KEYS_DIR}"/0x* | wc -l) keystores"

    # Copy proposer preferences config to VC directory
    echo "Importing proposer preferences config..."
    cp "${CHARON_CONFIG_DIR}/validators/validator_definitions.yml" "${VC_KEYS_DIR}/"
    echo "Imported proposer preferences config to ${VC_KEYS_DIR}/validator_definitions.yml"

    # Copy builder preferences config to VC directory
    echo "Importing builder preferences config..."
    cp "${CHARON_CONFIG_DIR}/validators/builder_definitions.yml" "${VC_KEYS_DIR}/"
    echo "Imported builder preferences config to ${VC_KEYS_DIR}/builder_definitions.yml"

    # Lighthouse runs from its own copy, .charon keeps none.
    rm -rf "${CHARON_KEYS_DIR}" "${CHARON_CONFIG_DIR}"
else
    echo "Nothing to import in .charon/vc-files, starting with the validator keys and settings imported before"
fi

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
