#!/usr/bin/env bash

# Docker creates missing bind mount directories as root. Start as root only to
# hand /home/user/data to uid 1000, then re-run this script as uid 1000.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 /home/user/data
  chmod 700 /home/user/data
  HOME="$(getent passwd 1000 | cut -d: -f6)" exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" "$@"
fi

# Remove previously imported keys, but keep the slashing protection DB
# (validators/slashing_protection.sqlite3*) across restarts.
rm -rf /home/user/data/secrets /home/user/data/validators/0x*

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

# Now run nimbus VC
exec /home/user/nimbus_validator_client \
  --data-dir=/home/user/data \
  --beacon-node="${BEACON_NODE_ADDRESS}" \
  --doppelganger-detection=false \
  --metrics \
  --metrics-address=0.0.0.0 \
  --payload-builder=${BUILDER_API_ENABLED} \
  --distributed
