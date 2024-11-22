#!/bin/bash

unset -v cluster_name

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo ""
 echo "Delete a validator cluster (Charon + VC + Prometheus), from the ./clusters directory."
 echo ""
 echo "Options:"
 echo " -h          Display this help message."
 echo " -c string   [REQUIRED] Name of the cluster to be deleted."
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

# Check if clusters dir already exists.
if test ! -d ./clusters/$cluster_name; then
  echo "./clsuters/$cluster_name directory does not exist. Make sure cluster $cluster_name is created."
  exit 1
fi

read -r -p "Are you sure you want to delete the cluster? This will delete your private keys, which will be unrecoverable if you do not have backup! [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    rm -rf ./clusters/$cluster_name
    echo "Cluster $cluster_name deleted."
fi
