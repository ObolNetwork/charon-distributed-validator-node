#!/bin/sh

if [ -z "$CHARON_LOKI_ADDRESSES" ]; then
  echo "Error: \$CHARON_LOKI_ADDRESSES variable is empty" >&2
  exit 1
fi

sed "s|\$CHARON_LOKI_ADDRESSES|${CHARON_LOKI_ADDRESSES}|g" \
    /etc/promtail/config.yml.example > /etc/promtail/config.yml

sed "s|\$CLUSTER_NAME|${CLUSTER_NAME}|g" \
    /etc/promtail/config.yml.example > /etc/promtail/config.yml

sed "s|\$CLUSTER_PEER|${CLUSTER_PEER}|g" \
    /etc/promtail/config.yml.example > /etc/promtail/config.yml

# Start Promtail with the generated config
/usr/bin/promtail \
  -config.file=/etc/promtail/config.yml
