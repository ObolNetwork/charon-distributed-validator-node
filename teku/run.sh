#!/bin/bash

# Use the charon-generated proposer config when available, otherwise fall back to a
# zero default fee recipient, which charon overrides pre-gloas.
PROPOSER_CONFIG=()
if [[ -f /opt/charon/vc-config/proposer-config.json ]]; then
    echo "proposer-config.json found, applying proposer settings"
    PROPOSER_CONFIG+=(--validators-proposer-config="/opt/charon/vc-config/proposer-config.json")
else
    echo "proposer-config.json not found, running with zero default fee recipient"
    PROPOSER_CONFIG+=(--validators-proposer-default-fee-recipient="0x0000000000000000000000000000000000000000")
fi

exec /opt/teku/bin/teku validator-client \
    --beacon-node-api-endpoint "${BEACON_NODE_ADDRESS}" \
    --network="${NETWORK}" \
    --data-base-path=/home/data \
    --validator-keys="/opt/charon/validator_keys:/opt/charon/validator_keys" \
    --validators-keystore-locking-enabled false \
    --validators-external-signer-slashing-protection-enabled true \
    --validators-builder-registration-default-enabled "${BUILDER_API_ENABLED}" \
    --Xobol-dvt-integration-enabled true \
    --Xvalidator-client-beacon-api-executor-threads=50 \
    "${PROPOSER_CONFIG[@]}"
