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
/validator wallet create --accept-terms-of-use --goerli --wallet-password-file=wallet-password.txt --keymanager-kind=direct --wallet-dir="$WALLET_DIR"

tmpkeys="/home/validator_keys/tmpkeys"
mkdir -p ${tmpkeys}

for f in /home/charon/validator_keys/keystore-*.json; do
    echo "Importing key ${f}"

    # Copy keystore file to tmpkeys/ directory.
    cp "${f}" "${tmpkeys}"

    # Import keystore with password.
    /validator accounts import \
        --keys-dir="/home/charon/validator_keys" \
        --goerli --accept-terms-of-use \
        --account-password-file="${f//json/txt}" \
        --wallet-password-file=wallet-password.txt \
        --wallet-dir="$WALLET_DIR"

    # Delete tmpkeys/keystore-*.json file that was copied before.
    filename="$(basename ${f})"
    rm "${tmpkeys}/${filename}"
done

# Delete the tmpkeys/ directory since it's no longer needed.
rm -r ${tmpkeys}

echo "Imported all keys"

# Now run prysm VC
/validator --wallet-dir="$WALLET_DIR" \
    --wallet-password-file="/wallet-password.txt" \
    --${ETH2_NETWORK} \
    --enable-beacon-rest-api \
    --accept-terms-of-use \
    --beacon-rest-api-provider="$BEACON_NODE_ADDRESS" \
    --distributed