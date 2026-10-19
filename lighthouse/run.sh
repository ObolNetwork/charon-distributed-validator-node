#!/bin/bash

KEYS_DIR="/opt/charon/validator_keys"
PROPOSER_CONFIG="/opt/charon/node/vc-config/proposer-config.json"
VALIDATORS_DIR="/opt/data/validators"
DEFINITIONS="${VALIDATORS_DIR}/validator_definitions.yml"

mkdir -p "${VALIDATORS_DIR}"

# On a fresh setup charon writes proposer-config.json shortly after it starts, wait for it.
for _ in $(seq 60); do
    [[ -f "${PROPOSER_CONFIG}" ]] && break
    sleep 2
done

# Author the validator definitions from the mounted charon keystores, replacing
# `lighthouse account validator import`. The file is regenerated on every start so
# proposer-config.json updates apply on restart; edit that file, not this one.
if [[ -f "${PROPOSER_CONFIG}" ]]; then
    echo "proposer-config.json found, applying proposer settings per validator"
else
    echo "proposer-config.json not found, generating validator definitions without proposer settings"
fi

rm -f "${DEFINITIONS}.tmp"
for keystore in "${KEYS_DIR}"/keystore-*.json; do
    pubkey="0x$(jq -r .pubkey "${keystore}")"

    {
        echo "- enabled: true"
        echo "  voting_public_key: \"${pubkey}\""
        echo "  type: local_keystore"
        echo "  voting_keystore_path: ${keystore}"
        echo "  voting_keystore_password_path: ${keystore%.json}.txt"

        if [[ -f "${PROPOSER_CONFIG}" ]]; then
            # Entries only carry fields diverging from default_config, absent fields fall back to it.
            fee_recipient=$(jq -r --arg pk "${pubkey}" '.proposer_config[$pk].fee_recipient // .default_config.fee_recipient' "${PROPOSER_CONFIG}")
            gas_limit=$(jq -r --arg pk "${pubkey}" '.proposer_config[$pk].gas_limit // .default_config.gas_limit' "${PROPOSER_CONFIG}")

            echo "  suggested_fee_recipient: \"${fee_recipient}\""
            echo "  gas_limit: ${gas_limit}"
            echo "  builder_proposals: ${BUILDER_API_ENABLED}"
        fi
    } >>"${DEFINITIONS}.tmp"
done
mv "${DEFINITIONS}.tmp" "${DEFINITIONS}"

echo "Generated ${DEFINITIONS}"

# From the gloas fork, Lighthouse requests bids from the builders in builder_definitions.yml and
# signs their builder request auths for charon to aggregate. Render it from charon's builder
# settings, builder entries fall back to them for absent fields. JSON is valid YAML.
BUILDERS="${VALIDATORS_DIR}/builder_definitions.yml"
rm -f "${BUILDERS}"
if [[ -f "${PROPOSER_CONFIG}" ]] && jq -e '.default_config.builder' "${PROPOSER_CONFIG}" >/dev/null; then
    jq '.default_config.builder as $d | {
        min_bid: ($d.min_bid | tonumber),
        builder_boost_factor: ($d.builder_boost_factor | tonumber),
        builders: [$d.builders[] | {
            enabled: true,
            url: .url,
            max_execution_payment: ((.max_execution_payment // $d.max_execution_payment) | tonumber)
        }
        + (if .min_bid then {min_bid: (.min_bid | tonumber)} else {} end)
        + (if .builder_boost_factor then {builder_boost_factor: (.builder_boost_factor | tonumber)} else {} end)]
    }' "${PROPOSER_CONFIG}" >"${BUILDERS}"
    echo "Generated ${BUILDERS}"
fi

EXTRA_FLAGS=()
if [[ ! -f "${PROPOSER_CONFIG}" ]]; then
    # Global fallbacks when validator definitions carry no proposer settings: the zero
    # default fee recipient, which charon overrides pre-gloas, and process-wide builder
    # participation. With a proposer config both are set per validator instead.
    EXTRA_FLAGS+=(--suggested-fee-recipient "0x0000000000000000000000000000000000000000")

    if [[ "${BUILDER_API_ENABLED}" == "true" ]]; then
        EXTRA_FLAGS+=(--builder-proposals)
    fi
fi

exec lighthouse validator_client \
    --network "${NETWORK}" \
    --datadir /opt/data \
    --beacon-nodes "${BEACON_NODE_ADDRESS}" \
    --distributed \
    --disable-auto-discover \
    --init-slashing-protection \
    --metrics \
    --metrics-address 0.0.0.0 \
    --metrics-port 5064 \
    "${EXTRA_FLAGS[@]}"
