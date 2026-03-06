#!/bin/sh

if [ -z "$SERVICE_OWNER" ]
then
  echo "\$SERVICE_OWNER variable is empty" >&2
  exit 1
fi

if [ -z "$PROM_REMOTE_WRITE_TOKEN" ]
then
  echo "\$PROM_REMOTE_WRITE_TOKEN variable is empty" >&2
  exit 1
fi

sed -e "s|\$PROM_REMOTE_WRITE_TOKEN|${PROM_REMOTE_WRITE_TOKEN}|g" \
    -e "s|\$SERVICE_OWNER|${SERVICE_OWNER}|g" \
    -e "s|\$CLUSTER_NAME|${CLUSTER_NAME}|g" \
    -e "s|\$CLUSTER_PEER|${CLUSTER_PEER}|g" \
    -e "s|\$ALERT_DISCORD_IDS|${ALERT_DISCORD_IDS}|g" \
    /etc/prometheus/prometheus.yml.example > /etc/prometheus/prometheus.yml

/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml
