#!/bin/sh

# The vc-bundle service renders Lodestar's keystores and proposer settings from .charon before this starts.
CHARON_BUNDLE_DIR="/opt/charon/node/vc-bundle"
CHARON_KEYS_DIR="${CHARON_BUNDLE_DIR}/keystores"
CHARON_SECRETS_DIR="${CHARON_BUNDLE_DIR}/secrets"
VC_DATA_DIR="/opt/data"
VC_KEYS_DIR="${VC_DATA_DIR}/keystores"
VC_SECRETS_DIR="${VC_DATA_DIR}/secrets"

# Copy validator keys to VC directory
echo "Importing validator keys..."
rm -rf "${VC_DATA_DIR}/cache" "${VC_KEYS_DIR}" "${VC_SECRETS_DIR}"
cp -r "${CHARON_KEYS_DIR}" "${VC_KEYS_DIR}"
cp -r "${CHARON_SECRETS_DIR}" "${VC_SECRETS_DIR}"

echo "Imported $(ls "${VC_KEYS_DIR}" | wc -l) keystores"

# Copy proposer preferences config to VC directory
# Copy builder preferences config to VC directory: Lodestar takes both from its proposer settings file
echo "Importing proposer and builder preferences config..."
cp "${CHARON_BUNDLE_DIR}/lodestar-proposer-settings.yml" "${VC_DATA_DIR}/"
echo "Imported proposer and builder preferences config to ${VC_DATA_DIR}/lodestar-proposer-settings.yml"

# --payloadLocal: charon expects the stateful gloas block form, the payload kept on the beacon node.
# --builder.selection=maxprofit: Lodestar applies the boost factor of the proposer settings file only with it.
# --allowDangerousTrustedPayments: Lodestar refuses to start on a builder max execution payment above 0 in the
# proposer settings without it. The cluster's proposer config sets that value, so it is allowed here.
exec node /usr/app/packages/cli/bin/lodestar validator \
    --dataDir="${VC_DATA_DIR}" \
    --keystoresDir="${VC_KEYS_DIR}" \
    --secretsDir="${VC_SECRETS_DIR}" \
    --network="${NETWORK}" \
    --metrics=true \
    --metrics.address="0.0.0.0" \
    --metrics.port=5064 \
    --beaconNodes="${BEACON_NODE_ADDRESS}" \
    --builder.selection=maxprofit \
    --proposerSettingsFile="${VC_DATA_DIR}/lodestar-proposer-settings.yml" \
    --distributed \
    --payloadLocal=true \
    --allowDangerousTrustedPayments
