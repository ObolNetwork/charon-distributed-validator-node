#!/bin/sh

if [ -z "${CHARON_LOKI_ADDRESSES:-}" ]; then
  echo "Error: \$CHARON_LOKI_ADDRESSES variable is empty" >&2
  exit 1
fi

if [ -z "${CLUSTER_NAME:-}" ]; then
  echo "Error: \$CLUSTER_NAME variable is empty" >&2
  exit 1
fi

if [ -z "${CLUSTER_PEER:-}" ]; then
  echo "Error: \$CLUSTER_PEER variable is empty" >&2
  exit 1
fi

SRC="/etc/alloy/config.alloy.example"
DST="/etc/alloy/config.alloy"

echo "Rendering template: $SRC -> $DST"

sed -e "s|\$CHARON_LOKI_ADDRESSES|${CHARON_LOKI_ADDRESSES}|g" \
    -e "s|\$CLUSTER_NAME|${CLUSTER_NAME}|g" \
    -e "s|\$CLUSTER_PEER|${CLUSTER_PEER}|g" \
    "$SRC" > "$DST"

echo "Config successfully rendered to $DST"

# Execute the command passed as arguments if any
if [ $# -gt 0 ]; then
  echo "Executing: $@"
  exec "$@"
fi
