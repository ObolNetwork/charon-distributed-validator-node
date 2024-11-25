#!/bin/bash

unset -v cluster_name

usage() {
 echo "Usage: $0 [OPTIONS] COMMAND"
 echo ""
 echo "    Manage a validator cluster (Charon + VC + Prometheus), found in ./clusters directory."
 echo ""
 echo "Commands:"
 echo "    add    string   Add a validator cluster to the ./clusters directory."
 echo "    delete string   Delete a validator cluster from the ./clusters directory."
 echo "    start  string   Start a validator cluster, found in the ./clusters directory."
 echo "    stop   string   Stop a validator cluster, found in the ./clusters directory."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
}

# Check if cluster_name variable is set.
check_missing_cluster_name() {
  if [ -z "$cluster_name" ]; then
    echo 'Missing cluster name argument.' >&2
    exit 1
  fi
}

# Check if ./clusters directory exists.
check_clusters_dir_does_not_exist() {
  if test ! -d ./clusters; then
    echo "./clsuters directory does not exist. Run setup.sh first."
    exit 1
  fi
}

# Check if cluster with the specified cluster_name already exists.
check_cluster_already_exists() {
  if test -d ./clusters/$cluster_name; then
    echo "./clsuters/$cluster_name directory already exists."
    exit 1
  fi
}

# Check if cluster with the specified cluster_name does not exist.
check_cluster_does_not_exist() {
  if test ! -d ./clusters/$cluster_name; then
    echo "./clsuters/$cluster_name directory does not exist."
    exit 1
  fi
}

# Add cluster to the ./clusters/{cluster_name} directory.
add() {
  find_port() {
    # Port number from which to start the search of free port.
    port=$1
    # Comma separated list of strings with ports to be explicitly excluded.
    # This is to prevent reusing the same port from inside the script (i.e.: if find_port is called multiple times, to avoid resulting in the same port)
    exclude=$2

    is_occupied=1
    # run loop until is_occupied is empty
    while [[ -n "$is_occupied" ]]; do
      # Check if TCP port is free, if it is, is_occupied is set to empty, otherwise increment the port by 1 and continue the loop.
      if is_occupied=$(netstat -taln | grep $port); then
        port=$(($port+1))
        continue
      fi
      # Check if TCP port is used by another cluster from the ./clusters directory.
      for cluster in ./clusters/*; do
        # Check if it is used by the p2p TCP port of this cluster.
        p2p_cluster_port=$(. ./$cluster/.env; printf '%s' "${CHARON_PORT_P2P_TCP}")
        # If the free port is the same as the port in the cluster, mark as occupied and break the loop.
        if [ $port -eq $p2p_cluster_port ]; then
          is_occupied=1
          break
        fi
      done
      # If the port was occupied by any cluster, increment the port by 1 and continue the loop.
      if [ ! -z "$is_occupied" ]; then
        port=$(($port+1))
        continue
      fi

      # Check if the port is not from the ports to be excluded.
      for i in ${exclude//,/ }
      do
        # If the port matches the potentially excluded port, mark as occupied, increment by 1 and break the loop.
        if [ $port -eq $i ]; then
          is_occupied=1
          port=$(($port+1))
          break
        fi
      done
    done

    # Echo the free port.
    echo $port
  }

  # Try to find free and unallocated to another cluster ports.
  p2p_port="$(find_port "3610" "CHARON_PORT_P2P_TCP" "")"

  # Create dir for the cluster.
  mkdir -p ./clusters/$cluster_name
  cluster_dir=./clusters/$cluster_name

  # Copy .env from root dir to cluster's dir (if it exists).
  if test ./.env; then
    cp .env ${cluster_dir}/
  fi

  # Copy docker-compose.yml from root dir to cluster's dir (if it exists).
  if test ./docker-compose.yml; then
    cp ./docker-compose.yml ${cluster_dir}/
  fi

  # Write the found free port in the .env file.
  if grep -xq "CHARON_PORT_P2P_TCP=.*" ./.env; then
    echo "CHARON_PORT_P2P_TCP already set, overwriting it with port $p2p_port"
    sed "s|CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=$p2p_port|" ${cluster_dir}/.env > ${cluster_dir}/.env.tmp
  else
    sed "s|#CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=$p2p_port|" ${cluster_dir}/.env > ${cluster_dir}/.env.tmp
  fi
  mv ${cluster_dir}/.env.tmp ${cluster_dir}/.env

  # Create data dir.
  mkdir ${cluster_dir}/data

  # Copy prometheus files and data.
  cp -r ./prometheus ${cluster_dir}/
  if test -d ./data/prometheus; then
    cp -r ./data/prometheus ${cluster_dir}/data/
  fi

  # Copy lodestar files.
  cp -r ./lodestar ${cluster_dir}/

  # Add the base network on which EL + CL + MEV-boost + Grafana run.
  sed "s|  dvnode:|  dvnode:\n  shared-node:\n      external:\n         name: charon-distributed-validator-node_dvnode|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml.tmp
  mv ${cluster_dir}/docker-compose.yml.tmp ${cluster_dir}/docker-compose.yml

  # Include the base network in the cluster-specific services' network config.
  sed "s|    networks: \[dvnode\]|    networks: [dvnode,shared-node]|" ${cluster_dir}/docker-compose.yml > ${cluster_dir}/docker-compose.yml.tmp
  mv ${cluster_dir}/docker-compose.yml.tmp ${cluster_dir}/docker-compose.yml

  echo "Added new cluster $cluster_name with the following cluster-specific config:"
  echo "CHARON_PORT_P2P_TCP: $p2p_port"
  echo ""
  echo "You can start it by running $0 start $cluster_name"
}

delete() {
  read -r -p "Are you sure you want to delete the cluster? This will delete your private keys, which will be unrecoverable if you do not have backup! [y/N] " response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
  then
      rm -rf ./clusters/$cluster_name
      echo "Delete cluster $cluster_name."
  fi
}

start() {
  docker compose --profile cluster -f ./clusters/${cluster_name}/docker-compose.yml up -d
  echo "Started cluster $cluster_name"
  echo "You can stop it by running $0 stop $cluster_name"
}

stop() {
  docker compose --profile cluster -f ./clusters/${cluster_name}/docker-compose.yml down
  echo "Stopped cluster $cluster_name"
  echo "You can start it again by running $0 start $cluster_name"
}

# Match global flags
while getopts ":h" opt; do
 case $opt in
  h)
    usage
    exit 0
    ;;
  \?) # unknown flag
    usage
    exit 1
    ;;
 esac
done

# Capture the subcommand passed.
shift "$((OPTIND -1))"
subcommand=$1; shift
# Execute subcommand.
case "$subcommand" in
  add)
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_already_exists
    add
    exit 0
    ;;
  delete)
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_does_not_exist
    delete
    exit 0
    ;;
  start)
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_does_not_exist
    start
    exit 0
    ;;
  stop)
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_does_not_exist
    stop
    exit 0
    ;;
  * )
    usage
    exit 1
    ;;
esac
