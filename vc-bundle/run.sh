#!/bin/sh

# Renders what the selected validator client consumes from .charon with `charon alpha vc-bundle`: the keystores
# in its layout, its proposer settings and the flags a distributed validator needs. It runs to completion before
# the validator client starts, so every start picks up the current proposer config.

CLIENT="${VC#vc-}"
NODE_DIR="/opt/charon/.charon"
PROPOSER_CONFIG_FILE="${NODE_DIR}/vc-config/proposer-config.json"
BUNDLE_DIR="${NODE_DIR}/vc-bundle"

if [ -z "${CLIENT}" ]; then
    echo "VC is not set, set it in .env to the validator client to render the bundle for"
    exit 1
fi

# On a fresh setup charon writes proposer-config.json shortly after it starts, wait for it.
for _ in $(seq 60); do
    [ -f "${PROPOSER_CONFIG_FILE}" ] && break
    sleep 2
done

# Start from an empty bundle, so files of removed validators are not picked up.
rm -rf "${BUNDLE_DIR}"

# Lighthouse's definitions point at the keystores by absolute path: /opt/charon/validator_keys is where the
# Lighthouse container mounts them too.
exec charon alpha vc-bundle "${CLIENT}" \
    --output-dir="${BUNDLE_DIR}" \
    --proposer-config-file="${PROPOSER_CONFIG_FILE}" \
    --validator-keys-dir=/opt/charon/validator_keys
