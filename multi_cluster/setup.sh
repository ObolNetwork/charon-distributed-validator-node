#!/bin/bash

current_cluster_name=default

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo ""
 echo "Create a multi-cluster setup from a traditional single cluster setup."
 echo ""
 echo "Options:"
 echo " -h          Display this help message."
 echo " -c string   Name of the current cluster. (default: \"default\")"
}

while getopts "hc:" opt; do
 case $opt in
   h)
    usage
    exit 0
    ;;
   c)
    current_cluster_name=${OPTARG}
    ;;
   \?)
    usage
    exit 1
    ;;
 esac
done

cluster_dir=./clusters/${current_cluster_name}

# Check if clusters dir already exists.
if test -d ./clusters; then
  echo "./clsuters directory already exists. Cannot setup already set multi cluster CDVN."
  exit 1
fi

# Create cluster's dir.
mkdir -p ${cluster_dir}

cleanupClusterDir() {
    if [ "$1" != "0" ]; then
      rm -rf ./clusters
    fi
}
trap 'cleanupClusterDir $?' EXIT

# Copy .charon folder to cluster's dir.
if test -d ./.charon; then
  cp -r .charon ${cluster_dir}/
fi

# Copy .env file to cluster's dir.
if test ./.env; then
  cp .env ${cluster_dir}/
fi

# Copy docker-compose.yml to cluster's dir.
if test ./docker-compose.yml; then
  cp ./docker-compose.yml ${cluster_dir}/
fi

# Write default charon ports in .env file if they are not set.
if grep -xq "CHARON_PORT_VALIDATOR_API=.*" ./.env; then
  echo "CHARON_PORT_VALIDATOR_API already set, using the set port instead of the default 3600"
else
  sed 's|#CHARON_PORT_VALIDATOR_API=|CHARON_PORT_VALIDATOR_API=3600|' ${cluster_dir}/.env > ${cluster_dir}/.env~
  mv ${cluster_dir}/.env~ ${cluster_dir}/.env
fi

if grep -xq "CHARON_PORT_MONITORING=.*" ./.env; then
  echo "CHARON_PORT_MONITORING already set, using the set port instead of the default 3620"
else
  sed 's|#CHARON_PORT_MONITORING=|CHARON_PORT_MONITORING=3620|' ${cluster_dir}/.env > ${cluster_dir}/.env~
  mv ${cluster_dir}/.env~ ${cluster_dir}/.env
fi

if grep -xq "CHARON_PORT_P2P_TCP=.*" ./.env; then
  echo "CHARON_PORT_P2P_TCP already set, using the set port instead of the default 3610"
else
  sed 's|#CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=3610|' ${cluster_dir}/.env > ${cluster_dir}/.env~
  mv ${cluster_dir}/.env~ ${cluster_dir}/.env
fi

# Create data dir
mkdir ${cluster_dir}/data

# Copy lodestar files and data
cp -r ./lodestar ${cluster_dir}/
if test -d ./data/lodestar; then
  cp -r ./data/lodestar ${cluster_dir}/data/
fi

# Copy prometheus files and data
cp -r ./prometheus ${cluster_dir}/
if test -d ./data/prometheus; then
  cp -r ./data/prometheus ${cluster_dir}/data/
fi

# Add the EL + CL + MEV-boost network
sed "s|  dvnode:|  dvnode:\n  shared-node:\n      external:\n         name: charon-distributed-validator-node_dvnode|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml~
mv ${cluster_dir}/docker-compose.yml~ ${cluster_dir}/docker-compose.yml

# Include the other services in the EL + CL + MEV-boost network
sed "s|    networks: \[dvnode\]|    networks: [dvnode,shared-node]|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml~
mv ${cluster_dir}/docker-compose.yml~ ${cluster_dir}/docker-compose.yml

# Stop the cluster-related containers that are running in root directory (i.e.: charon, VC).
docker compose --profile cluster down
# Start the base containers in root directory (i.e.: EL, CL).
docker compose --profile base up -d
# Start the cluster-related containers in cluster-specific directory (i.e.: charon, VC).
docker compose --profile cluster -f ${cluster_dir}/docker-compose.yml up -d
