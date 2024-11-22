#!/bin/bash

unset -v cluster_name

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo ""
 echo "Add a validator cluster (Charon + VC + Prometheus), to the ./clusters directory."
 echo ""
 echo "Options:"
 echo " -h          Display this help message."
 echo " -c string   [REQUIRED] Name of the cluster to be created."
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
if test -d ./clusters/$cluster_name; then
  echo "./clsuters/$cluster_name directory already exists."
  exit 1
fi

find_port() {
  port=$1 # Port number to start search from
  cluster_var=$2 # Env variable found in the cluster .env in ./clusters that is to be excluded
  exclude=$3 # Comma separated list of strings with ports already allocated from this script

  is_occupied=1
  while [[ -n "$is_occupied" ]]; do
    # Check if TCP port is free, if occupied increment with 1 and continue the loop
    if is_occupied=$(netstat -taln | grep $port); then
      port=$(($port+1))
      continue
    fi
    # Check if TCP port is used by another cluster
    for cluster in ./clusters/*; do
      p2p_cluster_port=$(. ./$cluster/.env; printf '%s' "${!cluster_var}")
      if [ $port -eq $p2p_cluster_port ]; then
        is_occupied=1
        break
      fi
    done
    # If occupied by cluster, increment with 1 and continue the loop
    if [ ! -z "$is_occupied" ]; then
      port=$(($port+1))
      continue
    fi

    for i in ${exclude//,/ }
    do
      if [ $port -eq $i ]; then
        is_occupied=1
        port=$(($port+1))
        break
      fi
    done
  done

  echo $port
}

# Try to find free and unallocated to another cluster p2p port
p2p_port="$(find_port "3610" "CHARON_PORT_P2P_TCP" "")"
validator_port="$(find_port "3600" "CHARON_PORT_VALIDATOR_API" "$p2p_port")"
monitoring_port="$(find_port "3620" "CHARON_PORT_MONITORING" "$p2p_port,$validator_port")"

mkdir -p ./clusters/$cluster_name
cluster_dir=./clusters/$cluster_name

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
  echo "CHARON_PORT_VALIDATOR_API already set, overwriting it with port $validator_port"
  sed "s|CHARON_PORT_VALIDATOR_API=|CHARON_PORT_VALIDATOR_API=$validator_port|" ${cluster_dir}/.env > ${cluster_dir}/.env~
else
  sed "s|#CHARON_PORT_VALIDATOR_API=|CHARON_PORT_VALIDATOR_API=$validator_port|" ${cluster_dir}/.env > ${cluster_dir}/.env~
fi
  mv ${cluster_dir}/.env~ ${cluster_dir}/.env

if grep -xq "CHARON_PORT_MONITORING=.*" ./.env; then
  echo "CHARON_PORT_MONITORING already set, overwriting it with port $monitoring_port"
  sed "s|CHARON_PORT_MONITORING=|CHARON_PORT_MONITORING=$monitoring_port|" ${cluster_dir}/.env > ${cluster_dir}/.env~
else
  sed "s|#CHARON_PORT_MONITORING=|CHARON_PORT_MONITORING=$monitoring_port|" ${cluster_dir}/.env > ${cluster_dir}/.env~
fi
mv ${cluster_dir}/.env~ ${cluster_dir}/.env

if grep -xq "CHARON_PORT_P2P_TCP=.*" ./.env; then
  echo "CHARON_PORT_P2P_TCP already set, overwriting it with port $p2p_port"
  sed "s|CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=$p2p_port|" ${cluster_dir}/.env > ${cluster_dir}/.env~
else
  sed "s|#CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=$p2p_port|" ${cluster_dir}/.env > ${cluster_dir}/.env~
fi
mv ${cluster_dir}/.env~ ${cluster_dir}/.env

# Create data dir
mkdir ${cluster_dir}/data

# Copy prometheus files and data
cp -r ./prometheus ${cluster_dir}/
if test -d ./data/prometheus; then
  cp -r ./data/prometheus ${cluster_dir}/data/
fi

# Copy lodestar files
cp -r ./lodestar ${cluster_dir}/

# Add the EL + CL + MEV-boost network
sed "s|  dvnode:|  dvnode:\n  shared-node:\n      external:\n         name: charon-distributed-validator-node_dvnode|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml~
mv ${cluster_dir}/docker-compose.yml~ ${cluster_dir}/docker-compose.yml

# Include the other services in the EL + CL + MEV-boost network
sed "s|    networks: \[dvnode\]|    networks: [dvnode,shared-node]|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml~
mv ${cluster_dir}/docker-compose.yml~ ${cluster_dir}/docker-compose.yml

echo "Added new cluster $cluster_name with the following cluster-specific config:"
echo "CHARON_PORT_P2P_TCP: $p2p_port"
echo "CHARON_PORT_VALIDATOR_API: $validator_port"
echo "CHARON_PORT_MONITORING: $monitoring_port"
