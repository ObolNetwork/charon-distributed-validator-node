#!/bin/bash

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo ""
 echo "Start the base docker containers (EL, CL, MEV boost, Grafana), without any validator."
 echo ""
 echo "Options:"
 echo " -h   Display this help message."
}

while getopts "hc:" opt; do
 case $opt in
   h)
    usage
    exit 0
    ;;
   \?)
    usage
    exit 1
    ;;
 esac
done

docker compose --profile base up -d
