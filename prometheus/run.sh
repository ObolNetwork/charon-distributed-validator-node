#!/bin/sh

if [ -z "$SERVICE_OWNER" ]
then
  echo "\$SERVICE_OWNER variable is empty"
fi

if [ -z "$PROM_REMOTE_WRITE_TOKEN" ]
then
  echo "\$PROM_REMOTE_WRITE_TOKEN variable is empty"
fi

# eval is used instead of envsubst, as prometheus user doesn't have permissions to install envsubst
eval "echo \"$(cat /etc/prometheus/prometheus.yml.example)\"" > /etc/prometheus/prometheus.yml

/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml
