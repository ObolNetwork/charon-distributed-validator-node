#!/usr/bin/env bash

WALLET_DIR="/prysm-wallet"

# Cleanup wallet directories if already exists.
rm -rf $WALLET_DIR
mkdir $WALLET_DIR

# Refer: https://docs.prylabs.network/docs/install/install-with-script#step-5-run-a-validator-using-prysm
# Running a prysm VC involves two steps which need to run in order:
# 1. Import validator keys in a prysm wallet account.
# 2. Run the validator client.
WALLET_PASSWORD="prysm-validator-secret"
echo $WALLET_PASSWORD > /wallet-password.txt
/app/cmd/validator/validator wallet create --accept-terms-of-use --wallet-password-file=wallet-password.txt --keymanager-kind=direct --wallet-dir="$WALLET_DIR"

tmpkeys="/home/validator_keys/tmpkeys"
mkdir -p ${tmpkeys}

for f in /home/charon/validator_keys/keystore-*.json; do
    echo "Importing key ${f}"

    # Copy keystore file to tmpkeys/ directory.
    cp "${f}" "${tmpkeys}"

    # Import keystore with password.
    /app/cmd/validator/validator accounts import \
        --accept-terms-of-use=true \
        --wallet-dir="$WALLET_DIR" \
        --keys-dir="${tmpkeys}" \
        --account-password-file="${f//json/txt}" \
        --wallet-password-file=wallet-password.txt

    # Delete tmpkeys/keystore-*.json file that was copied before.
    filename="$(basename ${f})"
    rm "${tmpkeys}/${filename}"
done

# Delete the tmpkeys/ directory since it's no longer needed.
rm -r ${tmpkeys}

echo "Imported all keys"

# Now run prysm VC
/app/cmd/validator/validator --wallet-dir="$WALLET_DIR" \
    --accept-terms-of-use=true \
    --datadir="/data/vc" \
    --wallet-password-file="/wallet-password.txt" \
    --enable-beacon-rest-api \
    --beacon-rest-api-provider="${BEACON_NODE_ADDRESS}" \
    --beacon-rpc-provider="${BEACON_NODE_ADDRESS}" \
    --"${NETWORK}" \
    --distributed
