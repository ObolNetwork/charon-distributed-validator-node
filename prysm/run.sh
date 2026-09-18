#!/usr/bin/env bash

WALLET_DIR="/prysm-wallet"

# Cleanup wallet directories if already exists.
rm -rf $WALLET_DIR
mkdir $WALLET_DIR

# Refer: https://prysm.offchainlabs.com/docs/install-prysm/install-with-script/#step-5-run-a-validator-using-prysm
# Running a prysm VC involves two steps which need to run in order:
# 1. Import validator keys in a prysm wallet account.
# 2. Run the validator client.
WALLET_PASSWORD="prysm-validator-secret"
echo $WALLET_PASSWORD > /wallet-password.txt
/app/cmd/validator/validator wallet create --accept-terms-of-use --wallet-password-file=wallet-password.txt --keymanager-kind=direct --wallet-dir="$WALLET_DIR"

tmpkeys="/home/validator_keys/tmpkeys"
mkdir -p ${tmpkeys}

for f in /home/charon/validator_keys/keystore-*.json; do
    echo "Importing key ${f}"

    # Copy keystore file to tmpkeys/ directory.
    cp "${f}" "${tmpkeys}"

    # Import keystore with password.
    /app/cmd/validator/validator accounts import \
        --accept-terms-of-use=true \
        --wallet-dir="$WALLET_DIR" \
        --keys-dir="${tmpkeys}" \
        --account-password-file="${f//json/txt}" \
        --wallet-password-file=wallet-password.txt

    # Delete tmpkeys/keystore-*.json file that was copied before.
    filename="$(basename ${f})"
    rm "${tmpkeys}/${filename}"
done

# Delete the tmpkeys/ directory since it's no longer needed.
rm -r ${tmpkeys}

echo "Imported all keys"

# Render Prysm's proposer settings from the charon-generated canonical config when available:
# entries only carry fields diverging from default_config, absent fields fall back to it.
# Builder configuration renders as the v2 schema, inherited per key from default_config.
PROPOSER_SETTINGS=()
if [[ -f /home/charon/vc-config/proposer-config.json ]]; then
    echo "proposer-config.json found, rendering prysm proposer settings"
    jq --argjson enabled "${BUILDER_API_ENABLED}" '
        .default_config as $d |
        ($d.builder != null) as $b |
        {
            proposer_config: (.proposer_config | map_values(
                {fee_recipient: (.fee_recipient // $d.fee_recipient)}
                + (if $b then {gas_limit: (.gas_limit // $d.gas_limit)} else {} end)
                + {builder: {enabled: $enabled, gas_limit: (.gas_limit // $d.gas_limit)}}
            )),
            default_config: (
                {fee_recipient: $d.fee_recipient}
                + (if $b then {gas_limit: $d.gas_limit} else {} end)
                + {builder: ({enabled: $enabled, gas_limit: $d.gas_limit} + ($d.builder // {}))}
            )
        }
        + (if $b then {version: 2} else {} end)' /home/charon/vc-config/proposer-config.json >/tmp/prysm-proposer-settings.json
    PROPOSER_SETTINGS+=(--proposer-settings-file="/tmp/prysm-proposer-settings.json")
else
    echo "proposer-config.json not found, running without proposer settings"
fi

# Now run prysm VC
exec /app/cmd/validator/validator --wallet-dir="$WALLET_DIR" \
    --accept-terms-of-use=true \
    --datadir="/data/vc" \
    --wallet-password-file="/wallet-password.txt" \
    --enable-beacon-rest-api \
    --monitoring-host=0.0.0.0 \
    --beacon-rest-api-provider="${BEACON_NODE_ADDRESS}" \
    --beacon-rpc-provider="${BEACON_NODE_ADDRESS}" \
    --"${NETWORK}" \
    --distributed \
    "${PROPOSER_SETTINGS[@]}"
