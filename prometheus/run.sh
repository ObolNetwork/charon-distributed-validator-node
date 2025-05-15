#!/bin/sh

if [ -z "$SERVICE_OWNER" ]
then
  echo "\$SERVICE_OWNER variable is empty"
fi

if [ -z "$PROM_REMOTE_WRITE_TOKEN" ]
then
  echo "\$PROM_REMOTE_WRITE_TOKEN variable is empty" >&2
  exit 1
fi

sed -e "s|\${PROM_REMOTE_WRITE_TOKEN}|${PROM_REMOTE_WRITE_TOKEN}|g" \
    -e "s|\${SERVICE_OWNER}|${SERVICE_OWNER}|g" \
    /etc/prometheus/prometheus.yml.example > /etc/prometheus/prometheus.yml

/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml
