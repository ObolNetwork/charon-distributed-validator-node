#!/bin/sh

for f in /home/charon/validator_keys/keystore-*.json; do
    echo "Importing key ${f}"

    # Import keystore with password.
    node /usr/app/packages/cli/bin/lodestar validator import \
        --dataDir="/opt/data" \
        --network="$NETWORK" \
        --importKeystores="$f" \
        --importKeystoresPassword="${f//json/txt}"
done

echo "Imported all keys"

exec node /usr/app/packages/cli/bin/lodestar validator \
    --dataDir="/opt/data" \
    --network="$NETWORK" \
    --metrics=true \
    --metrics.address="0.0.0.0" \
    --metrics.port=5064 \
    --beaconNodes="$BEACON_NODE_ADDRESS" \
    --distributed
