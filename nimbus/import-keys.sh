#!/usr/bin/env bash
# Import validator keystores into the Nimbus VC data directory (idempotent).
# Requires nimbus_beacon_node (from nimbus-eth2) at NIMBUS_BEACON_NODE.

set -euo pipefail

DATA_DIR="${DATA_DIR:-/home/user/data}"
VALIDATOR_KEYS_DIR="${VALIDATOR_KEYS_DIR:-/home/validator_keys}"
BEACON_NODE_BIN="${NIMBUS_BEACON_NODE:-/home/user/nimbus_beacon_node}"

if find "${DATA_DIR}/validators" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
  echo "Validators already present in ${DATA_DIR}/validators; skipping key import."
  exit 0
fi

if [ ! -x "${BEACON_NODE_BIN}" ]; then
  echo "Error: nimbus_beacon_node not found at ${BEACON_NODE_BIN}" >&2
  exit 1
fi

mkdir -p "${DATA_DIR}/validators"

tmpkeys="${VALIDATOR_KEYS_DIR}/tmpkeys"
mkdir -p "${tmpkeys}"

imported=0
for f in "${VALIDATOR_KEYS_DIR}"/keystore-*.json; do
  [ -e "$f" ] || continue
  echo "Importing key ${f}"

  password=$(<"${f//json/txt}")
  cp "${f}" "${tmpkeys}"

  echo "$password" |
    "${BEACON_NODE_BIN}" deposits import \
      --data-dir="${DATA_DIR}" \
      "${tmpkeys}"

  rm "${tmpkeys}/$(basename "${f}")"
  imported=$((imported + 1))
done

rm -rf "${tmpkeys}"

if [ "$imported" -eq 0 ]; then
  echo "Error: no keystore-*.json files found in ${VALIDATOR_KEYS_DIR}" >&2
  exit 1
fi

echo "Imported ${imported} key(s) into ${DATA_DIR}"
