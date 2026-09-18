#!/usr/bin/env bash

# Cleanup nimbus directories if they already exist.
rm -rf /home/user/data

# Refer: https://nimbus.guide/keys.html
# Running a nimbus VC involves two steps which need to run in order:
# 1. Importing the validator keys
# 2. And then actually running the VC
tmpkeys="/home/validator_keys/tmpkeys"
mkdir -p ${tmpkeys}

for f in /home/validator_keys/keystore-*.json; do
  echo "Importing key ${f}"

  # Read password from keystore-*.txt into $password variable.
  password=$(<"${f//json/txt}")

  # Copy keystore file to tmpkeys/ directory.
  cp "${f}" "${tmpkeys}"

  # Import keystore with the password.
  echo "$password" |
    /home/user/nimbus_beacon_node deposits import \
      --data-dir=/home/user/data \
      /home/validator_keys/tmpkeys

  # Delete tmpkeys/keystore-*.json file that was copied before.
  filename="$(basename ${f})"
  rm "${tmpkeys}/${filename}"
done

# Delete the tmpkeys/ directory since it's no longer needed.
rm -r ${tmpkeys}

echo "Imported all keys"

if [[ -f /home/charon/vc-config/proposer-config.json ]]; then
  echo "proposer-config.json found, rendering per-validator proposer settings"

  # Resolve each imported validator's settings: proposer_config entries only carry
  # fields diverging from default_config, absent fields fall back to it.
  config=/home/charon/vc-config/proposer-config.json
  for f in /home/validator_keys/keystore-*.json; do
    pubkey="0x$(jq -r .pubkey "${f}")"
    fee_recipient=$(jq -r --arg pk "${pubkey}" '.proposer_config[$pk].fee_recipient // .default_config.fee_recipient' "${config}")
    gas_limit=$(jq -r --arg pk "${pubkey}" '.proposer_config[$pk].gas_limit // .default_config.gas_limit' "${config}")

    for dir in "/home/user/data/validators/${pubkey}" "/home/user/data/validators/${pubkey#0x}"; do
      if [[ -d "${dir}" ]]; then
        echo "${fee_recipient}" >"${dir}/suggested_fee_recipient.hex"
        echo "${gas_limit}" >"${dir}/suggested_gas_limit.json"
      fi
    done
  done
else
  echo "proposer-config.json not found, running without proposer settings"
fi

# Now run nimbus VC
exec /home/user/nimbus_validator_client \
  --data-dir=/home/user/data \
  --beacon-node="${BEACON_NODE_ADDRESS}" \
  --doppelganger-detection=false \
  --metrics \
  --metrics-address=0.0.0.0 \
  --payload-builder="${BUILDER_API_ENABLED}" \
  --distributed
