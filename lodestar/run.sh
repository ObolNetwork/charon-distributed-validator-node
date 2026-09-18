#!/bin/sh

# Remove the existing keystores to avoid keystore locking issues.
rm -rf /opt/data/cache /opt/data/secrets /opt/data/keystores

DATA_DIR="/opt/data"
KEYSTORES_DIR="${DATA_DIR}/keystores"
SECRETS_DIR="${DATA_DIR}/secrets"

mkdir -p "${KEYSTORES_DIR}" "${SECRETS_DIR}"

IMPORTED_COUNT=0
EXISTING_COUNT=0

for f in /home/charon/validator_keys/keystore-*.json; do
    echo "Importing key ${f}"

    # Extract pubkey from keystore file
    PUBKEY="0x$(grep '"pubkey"' "$f" | awk -F'"' '{print $4}')"

    PUBKEY_DIR="${KEYSTORES_DIR}/${PUBKEY}"

    # Skip import if keystore already exists
    if [ -d "${PUBKEY_DIR}" ]; then
        EXISTING_COUNT=$((EXISTING_COUNT + 1))
        continue
    fi

    mkdir -p "${PUBKEY_DIR}"

    # Copy the keystore file to persisted keys backend
    install -m 600 "$f" "${PUBKEY_DIR}/voting-keystore.json"

    # Copy the corresponding password file
    PASSWORD_FILE="${f%.json}.txt"
    install -m 600 "${PASSWORD_FILE}" "${SECRETS_DIR}/${PUBKEY}"

    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
done

echo "Processed all keys imported=${IMPORTED_COUNT}, existing=${EXISTING_COUNT}, total=$(ls /home/charon/validator_keys/keystore-*.json | wc -l)"

# Render Lodestar's proposer settings from the charon-generated canonical config when
# available: entries only carry fields diverging from default_config, absent fields
# fall back to it. Lodestar only accepts yml/yaml file extensions; JSON is valid YAML.
PROPOSER_SETTINGS=""
if [ -f /home/charon/vc-config/proposer-config.json ]; then
    echo "proposer-config.json found, rendering lodestar proposer settings"
    node -e '
        const fs = require("fs");
        const src = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const d = src.default_config;
        const out = {
            proposer_config: {},
            default_config: {fee_recipient: d.fee_recipient, builder: {gas_limit: d.gas_limit}},
        };
        for (const [pubkey, entry] of Object.entries(src.proposer_config || {})) {
            out.proposer_config[pubkey] = {
                fee_recipient: entry.fee_recipient ?? d.fee_recipient,
                builder: {gas_limit: entry.gas_limit ?? d.gas_limit},
            };
        }
        fs.writeFileSync(process.argv[2], JSON.stringify(out));
    ' /home/charon/vc-config/proposer-config.json /tmp/proposer-config.yml
    PROPOSER_SETTINGS="--proposerSettingsFile=/tmp/proposer-config.yml"
else
    echo "proposer-config.json not found, running without proposer settings"
fi

# Word splitting of $PROPOSER_SETTINGS is intentional, it is empty or a single flag.
# shellcheck disable=SC2086
exec node /usr/app/packages/cli/bin/lodestar validator \
    --dataDir="$DATA_DIR" \
    --keystoresDir="$KEYSTORES_DIR" \
    --secretsDir="$SECRETS_DIR" \
    --network="$NETWORK" \
    --metrics=true \
    --metrics.address="0.0.0.0" \
    --metrics.port=5064 \
    --beaconNodes="$BEACON_NODE_ADDRESS" \
    --builder="$BUILDER_API_ENABLED" \
    --builder.selection="$BUILDER_SELECTION" \
    --distributed \
    $PROPOSER_SETTINGS
