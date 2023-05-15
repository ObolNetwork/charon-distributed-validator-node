#!/usr/bin/env bash

# Cleanup nimbus directories if they already exist.
rm -rf /home/user/data/${NODE}

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
  echo "$password" | \
  /home/user/nimbus_beacon_node deposits import \
  --data-dir=/home/user/data/${NODE} \
  /home/validator_keys/tmpkeys

  # Delete tmpkeys/keystore-*.json file that was copied before.
  filename="$(basename ${f})"
  rm "${tmpkeys}/${filename}"
done

# Delete the tmpkeys/ directory since it's no longer needed.
rm -r ${tmpkeys}

echo "Imported all keys"

# Now run nimbus VC
exec /home/user/nimbus_validator_client \
  --data-dir=/home/user/data/"${NODE}" \
  --beacon-node="http://$NODE:3600" \
  --doppelganger-detection=false \
  --metrics \
  --metrics-address=0.0.0.0
