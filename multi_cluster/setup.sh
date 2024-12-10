#!/bin/bash

# shellcheck disable=SC1090,SC1091,SC2012

cluster_already_set=

usage() {
  echo "Usage: $0 [OPTIONS] NAME"
  echo ""
  echo "    Create a multi cluster setup from a traditional single cluster setup. Name of the first cluster should be specified."
  echo ""
  echo "Options:"
  echo "    -h          Display this help message."
  echo ""
  echo "Example:"
  echo "  $0 initial-cluster"
}

while getopts "h:" opt; do
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
shift "$((OPTIND - 1))"
cluster_name=$1

if [ -z "$cluster_name" ]; then
  echo 'Missing cluster name argument.' >&2
  usage
  exit 1
fi

cluster_dir=./clusters/${cluster_name}

# Check if clusters directory already exists.
if test -d ./clusters; then
  echo "./clusters directory already exists. Cannot setup already set multi cluster CDVN."
  exit 1
fi

# Create clusters directory.
mkdir -p "$cluster_dir"

# Delete ./clusters dir if the script exits with non-zero code.
cleanupClusterDir() {
  if [ "$1" != "0" ]; then
    rm -rf ./clusters
  fi
}
trap 'cleanupClusterDir $?' EXIT

# Copy .charon folder to clusters directory (if it exists).
if test -d ./.charon; then
  owner="$(ls -ld ".charon" | awk '{print $3}')"
  if [ "$owner" = "$USER" ]; then
    cp -r .charon "$cluster_dir"/
    cluster_already_set=1
  else
    echo "current user ${USER} is not owner of .charon/"
    exit 1
  fi
fi

# Copy .env file to clusters directory (if it exists).
if test -f ./.env; then
  owner="$(ls -ld ".env" | awk '{print $3}')"
  if [ "${owner}" = "${USER}" ]; then
    cp .env "$cluster_dir"/
  else
    echo "current user ${USER} is not owner of .env"
    exit 1
  fi
fi

# Copy docker-compose.yml to clusters directory (if it exists).
if test -f ./docker-compose.yml; then
  owner="$(ls -ld "docker-compose.yml" | awk '{print $3}')"
  if [ "${owner}" = "${USER}" ]; then
    cp ./docker-compose.yml "$cluster_dir"/
  else
    echo "current user ${USER} is not owner of docker-compose.yml"
    exit 1
  fi
fi

# Write default charon ports in .env file if they are not set.
if grep -xq "CHARON_PORT_VALIDATOR_API=.*" ./.env; then
  echo "CHARON_PORT_VALIDATOR_API already set, using the set port instead of the default 3600"
else
  sed 's|#CHARON_PORT_VALIDATOR_API=|CHARON_PORT_VALIDATOR_API=3600|' "${cluster_dir}/.env" >"${cluster_dir}/.env~"
  mv "${cluster_dir}/.env~" "${cluster_dir}/.env"
fi

if grep -xq "CHARON_PORT_MONITORING=.*" ./.env; then
  echo "CHARON_PORT_MONITORING already set, using the set port instead of the default 3620"
else
  sed 's|#CHARON_PORT_MONITORING=|CHARON_PORT_MONITORING=3620|' "${cluster_dir}/.env" >"${cluster_dir}/.env~"
  mv "${cluster_dir}/.env~" "${cluster_dir}/.env"
fi

if grep -xq "CHARON_PORT_P2P_TCP=.*" ./.env; then
  echo "CHARON_PORT_P2P_TCP already set, using the set port instead of the default 3610"
else
  sed 's|#CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=3610|' "${cluster_dir}/.env" >"${cluster_dir}/.env~"
  mv "${cluster_dir}/.env~" "${cluster_dir}/.env"
fi

# Create data dir.
mkdir "${cluster_dir}/data"

# Copy lodestar files.
owner="$(ls -ld "lodestar" | awk '{print $3}')"
if [ "${owner}" = "${USER}" ]; then
  cp -r ./lodestar "${cluster_dir}/"
else
  echo "current user ${USER} is not owner of lodestar/"
  exit 1
fi

# Copy lodestar data, if it exists.
if test -d ./data/lodestar; then
  owner="$(ls -ld "data/lodestar" | awk '{print $3}')"
  if [ "${owner}" = "${USER}" ]; then
    cp -r ./data/lodestar "${cluster_dir}/data/"
  else
    echo "current user ${USER} is not owner of data/lodestar/"
    exit 1
  fi
fi

# Copy prometheus files.
owner="$(ls -ld "prometheus" | awk '{print $3}')"
if [ "${owner}" = "${USER}" ]; then
  cp -r ./prometheus "${cluster_dir}/"
else
  echo "current user ${USER} is not owner of prometheus/"
  exit 1
fi

# Copy prometheus data, if it exists.
if test -d ./data/prometheus; then
  owner="$(ls -ld "data/prometheus" | awk '{print $3}')"
  if [ "${owner}" = "${USER}" ]; then
    cp -r ./data/prometheus "${cluster_dir}/data/"
  else
    echo "current user ${USER} is not owner of data/prometheus/"
    exit 1
  fi
fi

# Add the base network on which EL + CL + MEV-boost + Grafana run.
sed "s|  dvnode:|  dvnode:\n  shared-node:\n      external:\n         name: charon-distributed-validator-node_dvnode|" "${cluster_dir}/docker-compose.yml" >"${cluster_dir}/docker-compose.yml~"
mv "${cluster_dir}/docker-compose.yml~" "${cluster_dir}/docker-compose.yml"

# Include the base network in the cluster-specific services' network config.
sed "s|    networks: \[dvnode\]|    networks: [dvnode,shared-node]|" "${cluster_dir}/docker-compose.yml" >"${cluster_dir}/docker-compose.yml~"
mv "${cluster_dir}/docker-compose.yml~" "${cluster_dir}/docker-compose.yml"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running, please start Docker first."
  exit 1
fi

# If containers were already started, restart the cluster with the new setup.
if [[ $(docker compose ps -aq) ]]; then
  echo "Restarting the cluster-specific containers from the new multi cluster directory ${cluster_dir}"
  # Stop the cluster-specific containers that are running in root directory - Charon, Lodestar, Prometheus.
  docker compose --profile cluster down
  # Start the base containers in the root directory.
  docker compose --profile base up -d
  # Start the cluster-specific containers in cluster-specific directory (i.e.: charon, VC).
  docker compose --profile cluster -f "${cluster_dir}/docker-compose.yml" up -d
fi

migrated_readme() {
  cat >"$1" <<EOL
THIS DIRECTORY HAS BEEN MIGRATED TO $2.
YOU SHOULD REFER TO CONFIGURATIONS AND DATA IN $2.
EOL
}

# Decomission cluster-specific directories and files
if test -d ./.charon; then
  mv ./.charon ./.charon-migrated-to-multi
  migrated_readme "./.charon-migrated-to-multi/README.md" "${cluster_dir}/.charon"
fi

if test -d ./data/lodestar; then
  mv ./data/lodestar ./data/lodestar-migrated-to-multi
  migrated_readme "./data/lodestar-migrated-to-multi/README.md" "${cluster_dir}/data/lodestar"
fi

if test -d ./data/prometheus; then
  mv ./data/prometheus ./data/prometheus-migrated-to-multi
  migrated_readme "./data/prometheus-migrated-to-multi/README.md" "${cluster_dir}/data/prometheus"
fi

echo "Multi cluster setup is complete."
echo "CDVN is divided in two:"
echo "  1. Ethereum node (EL + CL) and Grafana."
echo "  2. Multiple clusters, each consisting of Charon + Validator client + Prometheus."
if [ -z ${cluster_already_set+x} ]; then
  echo "Existing cluster was not found. You can create your new cluster from ${cluster_dir}."
else
  echo "All existing cluster-specific files from the CDVN directory are copied to the first cluster in the multi cluster setup at ${cluster_dir}."
  echo "Those are the .charon folder, data/lodestar and data/prometheus."
  echo "If you are using the multi cluster setup, you should refer to the configurations and data found in ${cluster_dir} from now on."
fi
echo "Separate clusters can be managed using the cluster.sh script."
echo "Ethereum node (EL + CL) and Grafana can be managed using the base.sh script."
