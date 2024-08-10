#!/usr/bin/env bash

_network="--network=${NETWORK}"

if [ "${BUILDER_API_ENABLED}" = "true" ]; then
  echo "MEV Boost enabled"
  _mev_boost="--validators-builder-registration-default-enabled --validators-proposer-blinded-blocks-enabled"
else
  _mev_boost=""
fi

_fee_recipient="--validators-proposer-default-fee-recipient=${FEE_RECIPIENT}"

exec "$@" ${_network} ${_mev_boost} ${_fee_recipient}
