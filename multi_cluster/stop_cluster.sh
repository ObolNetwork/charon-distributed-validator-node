#!/bin/bash

unset -v cluster_name

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo ""
 echo "Stop a validator cluster (Charon + VC + Prometheus), found in ./clusters directory."
 echo ""
 echo "Options:"
 echo " -h          Display this help message."
 echo " -c string   [REQUIRED] Name of the cluster to be stopped."
}

while getopts "hc:" opt; do
 case $opt in
   h)
    usage
    exit 0
    ;;
   c)
    cluster_name=${OPTARG}
    ;;
   \?)
    usage
    exit 1
    ;;
 esac
done

if [ -z "$cluster_name" ]; then
  echo 'Missing flag -c, cluster name is mandatory.' >&2
  exit 1
fi

# Check if clusters dir already exists.
if test ! -d ./clusters; then
  echo "./clsuters directory does not exist. Run setup.sh first."
  exit 1
fi

if test ! -d ./clusters/$cluster_name; then
  echo "./clsuters/$cluster_name directory does not exist. Run add-cluster.sh first."
  exit 1
fi

cluster_dir=./clusters/${cluster_name}

docker compose --profile cluster -f ${cluster_dir}/docker-compose.yml down
