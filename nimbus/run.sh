#!/usr/bin/env bash

# Docker creates missing bind mount directories as root. Start as root only to
# hand /home/user/data to uid 1000, then re-run this script as uid 1000.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 /home/user/data
  chmod 700 /home/user/data
  HOME="$(getent passwd 1000 | cut -d: -f6)" exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" "$@"
fi

# The vc-bundle service renders Nimbus's keystores, per-validator proposer settings and flags from .charon before
# this starts, in Nimbus's own validators/ and secrets/ layout.
BUNDLE_DIR="/opt/charon/node/vc-bundle"
DATA_DIR="/home/user/data"

# Replace the keystores and settings on every start, but keep the slashing protection DB
# (validators/slashing_protection.sqlite3*).
rm -rf "${DATA_DIR}/secrets" "${DATA_DIR}"/validators/0x*
mkdir -p "${DATA_DIR}/validators"
cp -r "${BUNDLE_DIR}/secrets" "${DATA_DIR}/secrets"
cp -r "${BUNDLE_DIR}"/validators/0x* "${DATA_DIR}/validators/"

echo "Imported $(ls -d "${DATA_DIR}"/validators/0x* | wc -l) keystores"

mapfile -t VC_FLAGS <"${BUNDLE_DIR}/vc-flags.txt"

exec /home/user/nimbus_validator_client \
  --data-dir="${DATA_DIR}" \
  --beacon-node="${BEACON_NODE_ADDRESS}" \
  --metrics \
  --metrics-address=0.0.0.0 \
  "${VC_FLAGS[@]}"
