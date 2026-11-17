#!/usr/bin/env bash

# The vc-bundle service renders Prysm's wallet and proposer settings from .charon before this starts. The wallet
# holds this node's key shares and its password file, so Prysm needs no import.
CHARON_BUNDLE_DIR="/opt/charon/node/vc-bundle"
CHARON_KEYS_DIR="${CHARON_BUNDLE_DIR}/prysm-wallet"
VC_DATA_DIR="/data/vc"
VC_KEYS_DIR="${VC_DATA_DIR}/prysm-wallet"

# Copy validator keys to VC directory
echo "Importing validator keys..."
rm -rf "${VC_KEYS_DIR}"
cp -r "${CHARON_KEYS_DIR}" "${VC_KEYS_DIR}"
echo "Imported the wallet holding the validator keys to ${VC_KEYS_DIR}"

# Copy proposer preferences config to VC directory
# Copy builder preferences config to VC directory: Prysm takes both from its proposer settings file
echo "Importing proposer and builder preferences config..."
cp "${CHARON_BUNDLE_DIR}/prysm-proposer-settings.json" "${VC_DATA_DIR}/"
echo "Imported proposer and builder preferences config to ${VC_DATA_DIR}/prysm-proposer-settings.json"

exec /app/cmd/validator/validator --wallet-dir="${VC_KEYS_DIR}" \
    --accept-terms-of-use=true \
    --datadir="${VC_DATA_DIR}" \
    --monitoring-host=0.0.0.0 \
    --beacon-rest-api-provider="${BEACON_NODE_ADDRESS}" \
    --beacon-rpc-provider="${BEACON_NODE_ADDRESS}" \
    --"${NETWORK}" \
    --proposer-settings-file="${VC_DATA_DIR}/prysm-proposer-settings.json" \
    --distributed \
    --enable-beacon-rest-api
