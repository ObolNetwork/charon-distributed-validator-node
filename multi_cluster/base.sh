#!/bin/bash

usage() {
 echo "Usage: $0 [OPTIONS] COMMAND"
 echo ""
 echo "    Manage the base ethereum node (EL, CL, MEV boost, Grafana), without interfering with any validator."
 echo ""
 echo "Commands:"
 echo "    start   Start an ethereum node, MEV-boost and Grafana."
 echo "    stop    Stop an ethereum node, MEV-boost and Grafana."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
}

usage_start() {
 echo "Usage: $0 start [OPTIONS]"
 echo ""
 echo "    Start the base ethereum node."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
 echo ""
 echo "Example:"
 echo "  $0 start"
}

usage_stop() {
 echo "Usage: $0 stop [OPTIONS]"
 echo ""
 echo "    Stop the base ethereum node."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
 echo ""
 echo "Example:"
 echo "  $0 stop"
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
    while getopts ":h" opt; do
      case $opt in
        h)
          usage_start
          exit 0
        ;;
        ? ) # Invalid option
          usage_start
          exit 1
        ;;
      esac
    done
    shift $((OPTIND-1))
    start
    ;;
  stop)
    while getopts ":h" opt; do
      case $opt in
        h)
          usage_stop
          exit 0
        ;;
        ? ) # Invalid option
          usage_stop
          exit 1
        ;;
      esac
    done
    shift $((OPTIND-1))
    stop
    ;;
  * )
    usage
    exit 1
    ;;

esac
