#!/bin/bash

# Docker creates missing bind mount directories as root. Start as root only to
# hand /home/data to uid 1000, then re-run this script as uid 1000.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 /home/data
  chmod 700 /home/data
  HOME="$(getent passwd 1000 | cut -d: -f6)" exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" "$@"
fi

# The vc-bundle service renders Teku's keystores, proposer config and flags from .charon before this starts.
BUNDLE_DIR="/opt/charon/node/vc-bundle"
mapfile -t VC_FLAGS <"${BUNDLE_DIR}/vc-flags.txt"

exec /opt/teku/bin/teku validator-client \
    --beacon-node-api-endpoint "${BEACON_NODE_ADDRESS}" \
    --network="${NETWORK}" \
    --data-base-path=/home/data \
    --validator-keys="${BUNDLE_DIR}/keystores:${BUNDLE_DIR}/keystores" \
    --validators-keystore-locking-enabled false \
    --validators-external-signer-slashing-protection-enabled true \
    --validators-builder-registration-default-enabled "${BUILDER_API_ENABLED}" \
    --validators-proposer-config="${BUNDLE_DIR}/teku-proposer-config.json" \
    --Xvalidator-client-beacon-api-executor-threads=50 \
    --metrics-enabled=true \
    --metrics-interface=0.0.0.0 \
    --metrics-port=8008 \
    --metrics-host-allowlist="*" \
    "${VC_FLAGS[@]}"
