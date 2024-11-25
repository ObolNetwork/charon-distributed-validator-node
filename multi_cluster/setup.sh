#!/bin/bash

current_cluster_name=default
cluster_already_set=

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo ""
 echo "    Create a multi cluster setup from a traditional single cluster setup."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
 echo "    -c string   Name of the current cluster. (default: \"default\")"
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

if [ "$current_cluster_name" = "default" ]; then
  echo "WARN: -c flag not specified. Using default cluster name 'default'."
fi

cluster_dir=./clusters/${current_cluster_name}

# Check if clusters directory already exists.
if test -d ./clusters; then
  echo "./clsuters directory already exists. Cannot setup already set multi cluster CDVN."
  exit 1
fi

# Create clusters directory.
mkdir -p ${cluster_dir}

# Delete ./clusters dir if the script exits with non-zero code.
cleanupClusterDir() {
    if [ "$1" != "0" ]; then
      rm -rf ./clusters
    fi
}
trap 'cleanupClusterDir $?' EXIT

# Copy .charon folder to clusters directory (if it exists).
if test -d ./.charon; then
  cp -r .charon ${cluster_dir}/
  cluster_already_set=1
fi

# Copy .env file to clusters directory (if it exists).
if test ./.env; then
  cp .env ${cluster_dir}/
fi

# Copy docker-compose.yml to clusters directory (if it exists).
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

  # Create data dir.
mkdir ${cluster_dir}/data

# Copy lodestar files and data.
cp -r ./lodestar ${cluster_dir}/
if test -d ./data/lodestar; then
  cp -r ./data/lodestar ${cluster_dir}/data/
fi

# Copy prometheus files and data.
cp -r ./prometheus ${cluster_dir}/
if test -d ./data/prometheus; then
  cp -r ./data/prometheus ${cluster_dir}/data/
fi

# Add the base network on which EL + CL + MEV-boost + Grafana run.
sed "s|  dvnode:|  dvnode:\n  shared-node:\n      external:\n         name: charon-distributed-validator-node_dvnode|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml~
mv ${cluster_dir}/docker-compose.yml~ ${cluster_dir}/docker-compose.yml

# Include the base network in the cluster-specific services' network config.
sed "s|    networks: \[dvnode\]|    networks: [dvnode,shared-node]|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml~
mv ${cluster_dir}/docker-compose.yml~ ${cluster_dir}/docker-compose.yml

# If containers were already started, restart the cluster with the new setup.
if [[ $(docker compose ps -aq) ]]; then
  echo "Restarting the cluster-specific containers from the new multi cluster directory ${cluster_dir}"
  # Stop the cluster-specific containers that are running in root directory - Charon, Lodestar, Prometheus.
  docker compose --profile cluster down
  # Start the base containers in the root directory.
  docker compose --profile base up -d
  # Start the cluster-specific containers in cluster-specific directory (i.e.: charon, VC).
  docker compose --profile cluster -f ${cluster_dir}/docker-compose.yml up -d
fi

echo "Multi cluster setup is complete."
echo "CDVN is divided in two:"
echo "  1. Ethereum node (EL + CL) and Grafana."
echo "  2. Multiple clusters, each consisting of Charon + Validator client + Prometheus."
if [ -z ${cluster_already_set+x} ] ; then
  echo "Existing cluster was not found. You can create your new cluster from ${cluster_dir}."
else
  echo "All existing cluster-specific files from the CDVN directory are copied to the first cluster in the multi cluster setup at ${cluster_dir}."
  echo "Those are the .charon folder, data/lodestar and data/prometheus."
  echo "If you are using the multi cluster setup, you should refer to the configurations and data found in ${cluster_dir} from now on."
fi
echo "Separate clusters can be managed using the cluster.sh script."
echo "Ethereum node (EL + CL) and Grafana can be managed using the base.sh script."
