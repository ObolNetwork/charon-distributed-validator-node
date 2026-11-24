#!/bin/sh

# Leaves what the selected validator client consumes in .charon/vc-files before it starts: its key shares in its
# layout with `charon alpha validator keys`, and its proposer settings and flags with `charon alpha validator config`.
# The validator client's run.sh moves them into its own data directory, so they only stay here until it starts.
# Every start of this service picks up the current proposer config.

set -e

CLIENT="${VC#vc-}"
NODE_DIR="/opt/charon/.charon"
PROPOSER_CONFIG_FILE="${NODE_DIR}/vc-config/proposer-config.json"
FILES_DIR="${NODE_DIR}/vc-files"

if [ -z "${CLIENT}" ]; then
    echo "VC is not set, set it in .env to the validator client to write the files for"
    exit 1
fi

# On a fresh setup charon writes proposer-config.json shortly after it starts, wait for it.
for _ in $(seq 60); do
    [ -f "${PROPOSER_CONFIG_FILE}" ] && break
    sleep 2
done

# Start from empty directories, so files of removed validators or of a client used before are not kept. The
# directory itself stays, the validator clients mount it.
mkdir -p "${FILES_DIR}"
chmod 700 "${FILES_DIR}"
rm -rf "${FILES_DIR}/keys" "${FILES_DIR}/config"

# Lighthouse's definitions name the keystores by absolute path under its data directory: /opt/data in its
# container, where its run.sh copies them. The other clients ignore --lighthouse-dir.
if charon alpha validator keys "${CLIENT}" \
    --output-dir="${FILES_DIR}/keys" \
    --validator-keys-dir="${NODE_DIR}/validator_keys" &&
    charon alpha validator config "${CLIENT}" \
        --output-dir="${FILES_DIR}/config" \
        --proposer-config-file="${PROPOSER_CONFIG_FILE}" \
        --validator-keys-dir="${NODE_DIR}/validator_keys" \
        --lighthouse-dir=/opt/data; then
    exit 0
fi

# A proposer config the client cannot take must not stop the validator client: it keeps what it imported before.
rm -rf "${FILES_DIR}/keys" "${FILES_DIR}/config"
echo "WARNING: writing the ${CLIENT} keys and proposer settings failed, the validator client starts with the ones it imported before"
