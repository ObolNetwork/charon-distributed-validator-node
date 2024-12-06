#!/bin/bash

unset -v cluster_name
skip_port_free_check=
p2p_default_port=3610

usage_base() {
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

usage_add() {
 echo "Usage: $0 add [OPTIONS] NAME"
 echo ""
 echo "    Add a new cluster with specified name."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
 echo "    -s          Skip free port checking with netstat/ss."
 echo "    -p integer  Override the default port (3610) from which to start the search of a free port."
}

usage_delete() {
 echo "Usage: $0 delete [OPTIONS] NAME"
 echo ""
 echo "    Delete an existing cluster with the specified name. A cluster name is a folder in ./clusters dir."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
}

usage_start() {
 echo "Usage: $0 start [OPTIONS] NAME"
 echo ""
 echo "    Start an existing cluster with the specified name. A cluster name is a folder in ./clusters dir."
 echo ""
 echo "Options:"
 echo "    -h          Display this help message."
}

usage_stop() {
 echo "Usage: $0 stop [OPTIONS] NAME"
 echo ""
 echo "    Stop an existing cluster with the specified name. A cluster name is a folder in ./clusters dir."
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
  # Try to find free and unallocated to another cluster ports.
  # Port number from which to start the search of free port, default is 3610.
  port=$p2p_default_port

  is_occupied=1
  # Run loop until is_occupied is empty.
  while [[ -n "$is_occupied" ]]; do
    # Check if TCP port is free, if it is, is_occupied is set to empty, otherwise increment the port by 1 and continue the loop.
    if [ -z ${skip_port_free_check} ] ; then
      if [ -x "$(command -v netstat)" ]; then
        if is_occupied=$(netstat -taln | grep $port); then
          port=$(($port+1))
          continue
        fi
      elif [ -x "$(command -v ss)" ]; then
        if is_occupied=$(ss -taln | grep $port); then
          port=$(($port+1))
          continue
        fi
      else
        echo "Neither netstat or ss commands found. Please install either of those to check for free ports or add the -p flag to skip port check."
        exit 1
      fi
    else
      # Assume port is not occupied if no netstat/ss check.
      is_occupied=
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

    # Check if TCP port is used by the base.

    # Fetch the NETHERMIND_PORT_P2P from the base .env file.
    nethermind_p2p_port=$(. ./.env; printf '%s' "${NETHERMIND_PORT_P2P}")
    # If the NETHERMIND_PORT_P2P is not set and the free port is the same as the default one, increment the port by 1 and continue the loop.
    if [ -z "$nethermind_p2p_port" ]; then
      if [ "$port" -eq "30303" ]; then
        port=$(($port+1))
        continue
      fi
    # If the NETHERMIND_PORT_P2P is set and the free port is the same, increment the port by 1 and continue the loop.
    elif [ $port -eq $nethermind_p2p_port ]; then
      port=$(($port+1))
      continue
    fi

    # Fetch the NETHERMIND_PORT_HTTP from the base .env file.
    nethermind_http_port=$(. ./.env; printf '%s' "${NETHERMIND_PORT_HTTP}")
    # If the NETHERMIND_PORT_HTTP is not set and the free port is the same as the default one, increment the port by 1 and continue the loop.
    if [ -z "$nethermind_http_port" ]; then
      if [ "$port" -eq "8545" ]; then
        port=$(($port+1))
        continue
      fi
    # If the NETHERMIND_PORT_HTTP is set and the free port is the same, increment the port by 1 and continue the loop.
    elif [ $port -eq $nethermind_http_port ]; then
      port=$(($port+1))
      continue
    fi

    # Fetch the NETHERMIND_PORT_ENGINE from the base .env file.
    nethermind_engine_port=$(. ./.env; printf '%s' "${NETHERMIND_PORT_ENGINE}")
    # If the NETHERMIND_PORT_ENGINE is not set and the free port is the same as the default one, increment the port by 1 and continue the loop.
    if [ -z "$nethermind_engine_port" ]; then
      if [ "$port" -eq "8551" ]; then
        port=$(($port+1))
        continue
      fi
    # If the NETHERMIND_PORT_ENGINE is set and the free port is the same, increment the port by 1 and continue the loop.
    elif [ $port -eq $nethermind_engine_port ]; then
      port=$(($port+1))
      continue
    fi

    # Fetch the LIGHTHOUSE_PORT_P2P from the base .env file.
    lighthouse_p2p_port=$(. ./.env; printf '%s' "${LIGHTHOUSE_PORT_P2P}")
    # If the LIGHTHOUSE_PORT_P2P is not set and the free port is the same as the default one, increment the port by 1 and continue the loop.
    if [ -z "$lighthouse_p2p_port" ]; then
      if [ "$port" -eq "9000" ]; then
        port=$(($port+1))
        continue
      fi
    # If the LIGHTHOUSE_PORT_P2P is set and the free port is the same, increment the port by 1 and continue the loop.
    elif [ $port -eq $lighthouse_p2p_port ]; then
      port=$(($port+1))
      continue
    fi
  done


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
    echo "CHARON_PORT_P2P_TCP already set, overwriting it with port $port"
    sed "s|CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=$port|" ${cluster_dir}/.env > ${cluster_dir}/.env.tmp
  else
    sed "s|#CHARON_PORT_P2P_TCP=|CHARON_PORT_P2P_TCP=$port|" ${cluster_dir}/.env > ${cluster_dir}/.env.tmp
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
  echo "CHARON_PORT_P2P_TCP: $port"
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
    usage_base
    exit 0
    ;;
  \?) # unknown flag
    usage_base
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
    while getopts ":hsp:" opt; do
      case $opt in
        h)
          usage_add
          exit 0
        ;;
        s )
          skip_port_free_check=true
        ;;
        p )
          p2p_default_port=${OPTARG};
        ;;
        ? ) # Invalid option
          usage_add
          exit 1
        ;;
      esac
    done
    shift "$((OPTIND -1))"
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_already_exists
    add
    exit 0
    ;;
  delete)
      while getopts ":h" opt; do
      case $opt in
        h)
          usage_delete
          exit 0
        ;;
        ? ) # Invalid option
          usage_delete
          exit 1
        ;;
      esac
    done
    shift $((OPTIND-1))
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_does_not_exist
    delete
    exit 0
    ;;
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
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_does_not_exist
    start
    exit 0
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
    cluster_name=$1
    check_missing_cluster_name
    check_clusters_dir_does_not_exist
    check_cluster_does_not_exist
    stop
    exit 0
    ;;
  * )
    usage_base
    exit 1
    ;;
esac
