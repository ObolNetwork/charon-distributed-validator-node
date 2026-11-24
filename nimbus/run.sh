#!/usr/bin/env bash

# The vc-files service leaves Nimbus's keystores, per-validator proposer settings and flags in .charon/vc-files
# before this starts, in Nimbus's own layout: a directory per validator with its keystore and settings, the
# passwords apart.
CHARON_KEYS_DIR="/opt/charon/vc-files/keys"
CHARON_CONFIG_DIR="/opt/charon/vc-files/config"
VC_DATA_DIR="/home/user/data"
VC_KEYS_DIR="${VC_DATA_DIR}/validators"
VC_SECRETS_DIR="${VC_DATA_DIR}/secrets"

# Docker creates missing bind mount directories as root. Start as root only to
# hand the data directory to uid 1000, then re-run this script as uid 1000.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "${VC_DATA_DIR}"
  chmod 700 "${VC_DATA_DIR}"
  HOME="$(getent passwd 1000 | cut -d: -f6)" exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" "$@"
fi

if [ -d "${CHARON_KEYS_DIR}" ]; then
    # Replace the keystores and settings, but keep the slashing protection DB
    # (validators/slashing_protection.sqlite3*).
    rm -rf "${VC_SECRETS_DIR}" "${VC_KEYS_DIR}"/0x*
    mkdir -p "${VC_KEYS_DIR}"

    # Copy validator keys to VC directory
    echo "Importing validator keys..."
    cp -r "${CHARON_KEYS_DIR}/secrets" "${VC_SECRETS_DIR}"
    cp -r "${CHARON_KEYS_DIR}/validators"/0x* "${VC_KEYS_DIR}/"
    echo "Imported $(ls -d "${VC_KEYS_DIR}"/0x* | wc -l) keystores"

    # Copy proposer preferences config to VC directory: each validator's directory holds its settings beside its keystore
    echo "Importing proposer preferences config..."
    cp -r "${CHARON_CONFIG_DIR}/validators"/0x* "${VC_KEYS_DIR}/"
    echo "Imported proposer preferences config to ${VC_KEYS_DIR}"

    # Copy builder preferences config to VC directory: Nimbus takes it as flags only, so vc-flags.txt holds them with
    # the flags a distributed validator needs.
    echo "Importing builder preferences config as flags..."
    cp "${CHARON_CONFIG_DIR}/vc-flags.txt" "${VC_DATA_DIR}/"
    echo "Imported builder preferences config as flags from vc-flags.txt: Nimbus doesn't read a builder config file"

    # Nimbus runs from its own copy, .charon keeps none.
    rm -rf "${CHARON_KEYS_DIR}" "${CHARON_CONFIG_DIR}"
else
    echo "Nothing to import in .charon/vc-files, starting with the validator keys and settings imported before"
fi

mapfile -t VC_FLAGS <"${VC_DATA_DIR}/vc-flags.txt"

exec /home/user/nimbus_validator_client \
  --data-dir="${VC_DATA_DIR}" \
  --beacon-node="${BEACON_NODE_ADDRESS}" \
  --metrics \
  --metrics-address=0.0.0.0 \
  "${VC_FLAGS[@]}"
