#!/bin/bash

usage() {
 echo "Usage: $0 [OPTIONS] COMMAND"
 echo ""
 echo "    Manage the base ethereum node docker containers (EL, CL, MEV boost, Grafana), without interfering with any validator."
 echo ""
 echo "Commands:"
 echo "    start   Start an ethereum node, MEV-boost and Grafana."
 echo "    stop    Stop an ethereum node, MEV-boost and Grafana."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
}

start() {
  docker compose --profile base up -d
}

stop() {
  docker compose --profile base stop
}

while getopts ":h" opt; do
 case $opt in
  h)
    usage
    exit 0
    ;;
  \?)
    usage
    exit 1
    ;;
  : )
    usage
    exit 1
    ;;
 esac
done

shift $((OPTIND -1))

subcommand=$1; shift
case "$subcommand" in
  # Parse options to the install sub command
  start)
    start
    ;;
  stop)
    stop
    ;;
  * )
    usage
    exit 1
    ;;

esac
