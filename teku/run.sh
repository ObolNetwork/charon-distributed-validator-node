#!/bin/bash

# Render Teku's proposer config from the charon-generated canonical config when available:
# entries only carry fields diverging from default_config, absent fields fall back to it.
# Otherwise fall back to a zero default fee recipient, which charon overrides pre-gloas.
PROPOSER_CONFIG=()
if [[ -f /opt/charon/vc-config/proposer-config.json ]]; then
    echo "proposer-config.json found, rendering teku proposer config"
    jq --argjson enabled "${BUILDER_API_ENABLED}" '
        .default_config as $d |
        {
            proposer_config: (.proposer_config | map_values({
                fee_recipient: (.fee_recipient // $d.fee_recipient),
                builder: {enabled: $enabled, gas_limit: (.gas_limit // $d.gas_limit)}
            })),
            default_config: {
                fee_recipient: $d.fee_recipient,
                builder: {enabled: $enabled, gas_limit: $d.gas_limit}
            }
        }' /opt/charon/vc-config/proposer-config.json >/tmp/teku-proposer-config.json
    PROPOSER_CONFIG+=(--validators-proposer-config="/tmp/teku-proposer-config.json")
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
    --metrics-enabled=true \
    --metrics-interface=0.0.0.0 \
    --metrics-port=8008 \
    --metrics-host-allowlist="*" \
    "${PROPOSER_CONFIG[@]}"
