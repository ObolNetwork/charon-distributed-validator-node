#!/usr/bin/env bash

# Docker creates missing bind mount directories as root. Start as root only to
# hand /home/data to uid 1000, then re-run this script as uid 1000.
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 /home/data
  chmod 700 /home/data
  HOME="$(getent passwd 1000 | cut -d: -f6)" exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" "$@"
fi

exec /opt/teku/bin/teku "$@"
