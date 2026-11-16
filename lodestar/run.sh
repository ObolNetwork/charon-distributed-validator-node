#!/bin/sh

# The vc-bundle service renders Lodestar's keystores, proposer settings and flags from .charon before this starts.
BUNDLE_DIR="/opt/charon/node/vc-bundle"
DATA_DIR="/opt/data"
KEYSTORES_DIR="${DATA_DIR}/keystores"
SECRETS_DIR="${DATA_DIR}/secrets"

# Replace the keystores on every start, which also avoids keystore locking issues.
rm -rf "${DATA_DIR}/cache" "${KEYSTORES_DIR}" "${SECRETS_DIR}"
cp -r "${BUNDLE_DIR}/keystores" "${KEYSTORES_DIR}"
cp -r "${BUNDLE_DIR}/secrets" "${SECRETS_DIR}"

echo "Imported $(ls "${KEYSTORES_DIR}" | wc -l) keystores"

# Append the flags of vc-flags.txt, one per line.
set --
while IFS= read -r flag; do
    set -- "$@" "${flag}"
done <"${BUNDLE_DIR}/vc-flags.txt"

exec node /usr/app/packages/cli/bin/lodestar validator \
    --dataDir="${DATA_DIR}" \
    --keystoresDir="${KEYSTORES_DIR}" \
    --secretsDir="${SECRETS_DIR}" \
    --network="${NETWORK}" \
    --metrics=true \
    --metrics.address="0.0.0.0" \
    --metrics.port=5064 \
    --beaconNodes="${BEACON_NODE_ADDRESS}" \
    --builder.selection="${BUILDER_SELECTION}" \
    --proposerSettingsFile="${BUNDLE_DIR}/lodestar-proposer-settings.yml" \
    "$@"
