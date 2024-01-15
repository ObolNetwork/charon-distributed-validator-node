#!/bin/sh

BUILDER_SELECTION="executiononly"

# If the builder API is enabled, override the builder selection to signal Lodestar to always propose blinded blocks.
if [[ $BUILDER_API_ENABLED == "true" ]];
then
  BUILDER_SELECTION="builderonly"
fi

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
    --builder="$BUILDER_API_ENABLED" \
    --builder.selection="$BUILDER_SELECTION" \
    --distributed \
    --useProduceBlockV3=false
