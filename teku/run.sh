#!/bin/bash

# The vc-bundle service renders Teku's keystores and proposer config from .charon before this starts.
CHARON_BUNDLE_DIR="/opt/charon/node/vc-bundle"
CHARON_KEYS_DIR="${CHARON_BUNDLE_DIR}/keystores"
VC_DATA_DIR="/home/data"
VC_KEYS_DIR="${VC_DATA_DIR}/keystores"

# Docker creates missing bind mount directories as root. Start as root only to
# hand the data directory to uid 1000, then re-run this script as uid 1000.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "${VC_DATA_DIR}"
  chmod 700 "${VC_DATA_DIR}"
  HOME="$(getent passwd 1000 | cut -d: -f6)" exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" "$@"
fi

# Copy validator keys to VC directory
echo "Importing validator keys..."
rm -rf "${VC_KEYS_DIR}"
cp -r "${CHARON_KEYS_DIR}" "${VC_KEYS_DIR}"
echo "Imported $(ls "${VC_KEYS_DIR}"/*.json | wc -l) keystores"

# Copy proposer preferences config to VC directory
# Copy builder preferences config to VC directory: Teku takes both from its proposer config file
echo "Importing proposer and builder preferences config..."
cp "${CHARON_BUNDLE_DIR}/teku-proposer-config.json" "${VC_DATA_DIR}/"
echo "Imported proposer and builder preferences config to ${VC_DATA_DIR}/teku-proposer-config.json"

exec /opt/teku/bin/teku validator-client \
    --beacon-node-api-endpoint "${BEACON_NODE_ADDRESS}" \
    --network="${NETWORK}" \
    --data-base-path="${VC_DATA_DIR}" \
    --validator-keys="${VC_KEYS_DIR}:${VC_KEYS_DIR}" \
    --validators-keystore-locking-enabled false \
    --validators-external-signer-slashing-protection-enabled true \
    --validators-builder-registration-default-enabled "${BUILDER_API_ENABLED}" \
    --validators-proposer-config="${VC_DATA_DIR}/teku-proposer-config.json" \
    --Xvalidator-client-beacon-api-executor-threads=50 \
    --metrics-enabled=true \
    --metrics-interface=0.0.0.0 \
    --metrics-port=8008 \
    --metrics-host-allowlist="*" \
    --Xobol-dvt-integration-enabled=true
