#!/usr/bin/env bash

__network="--network=${NETWORK}"

if [ "${BUILDER_API_ENABLED}" = "true" ]; then
  __mev_boost="--validators-builder-registration-default-enabled --validators-proposer-blinded-blocks-enabled"
  echo "MEV Boost enabled"
else
  __mev_boost=""
fi

__fee_recipient="--validators-proposer-default-fee-recipient=${FEE_RECIPIENT}"

exec "$@" ${__network} ${__mev_boost} ${__fee_recipient}