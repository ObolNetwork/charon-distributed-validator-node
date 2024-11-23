![Obol Logo](https://obol.tech/obolnetwork.png)

<h1 align="center">Charon Distributed Validator Node</h1>

This repo contains the [docker-compose](https://docs.docker.com/compose/) files needed to run one node in a [charon](https://github.com/ObolNetwork/charon) [Distributed Validator Cluster](https://docs.obol.tech/docs/int/key-concepts#distributed-validator-cluster).

A distributed validator node is a machine running:

- An Ethereum Execution client
- An Ethereum Consensus client
- An Ethereum Distributed Validator client
- An Ethereum Validator client

![Distributed Validator Node](DVNode.png)

# Quickstart

Check the Obol [docs](https://docs.obol.tech/docs/start/quickstart_overview) for detailed instructions on how to get started using this repo.

# Examples

A default example configuration of a full validator node is found in the root `docker-compose.yml` file.

The `examples/` directory is under development, you will find a collection of docker compose configuration files that demonstrate various clients and their configurations for running a Distributed Validator Node. These files are with filenames as {EC}-{CC}-{VC}.yml (where EC: Execution Client, CC: Consensus Client, VC: Validator Client). For example, if you wish to run a DV node with Geth EL, Teku CL and Lighthouse VC, you can run `geth_teku_lighthouse.yml`.

⚠️⚠️⚠️ **Important:**
The configurations provided are meant for demonstration purposes only and may not be suitable for production environments.
These examples are primarily intended for advanced users who are familiar with Docker and have a good understanding of execution and consensus clients.
Please exercise caution when using them and ensure that you thoroughly review and customize the configurations according to your specific requirements.

To run the default example, use the following command:

```sh
docker compose up
```

To run any of the other examples, found in `examples/` use the following command:

```sh
docker compose -f examples/nethermind_teku_lighthouse.yml up
```

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/faq/errors)

<!-- TODO: move this guide to the docs -->
# Multi cluster setup

There is an option to run multiple Charon clusters using the same Execution Client, Consensus Client and Grafana. This way you can operate multiple clusters for different purposes, without putting much more pressure on your system.

## Setup

If you already have running validator node in Docker, the Docker containers will be moved to the new multi cluster setup.

```bash
./multi_cluster/setup.sh -c {YOUR_CLUSTER_NAME}
```

You can inspect what you have in the `./clusters/` directory. Each subfolder is a cluster with the following structure:

```directory
clusters
└───{YOUR_CLUSTER_NAME}     # cluster name
│   │   .charon             # folder including secret material used by charon
│   │   data                # data from the validator client and prometheus
│   │   lodestar            # scripts used by lodestar
│   │   prometheus          # scripts and configs used by prometheus
│   │   .env                # environment variables used by the cluster
│   │   docker-compose.yml  # docker compose used by the cluster
│                           # N.B.: only services with profile "cluster" are ran
└───{YOUR_CLUSTER_NAME_2}
└───{YOUR_CLUSTER_NAME_...}
└───{YOUR_CLUSTER_NAME_N}
```

Note that those folders and files are copied from the root directory. Meaning all configurations and setup you have already done, will be copied to this first cluster of the multi cluster setup.

## Manage cluster

Manage the Charon + Validator Client + Prometheus containers of each cluster found in `./clusters/`.

### Add cluster

```bash
./multi_cluster/cluster.sh add {YOUR_CLUSTER_NAME}
```

Note that only the `.env`, `lodestar/`, `prometheus/` and `docker-compose.yml` files and directories are coiped from the root directory to the new cluster. `.charon/` and `data/` folders are expected to be from a brand new cluster that you will setup in the `./clusters/{YOUR_CLUSTER_NAME}` directory.

### Start cluster

It is expected that you have already done the regular procedure from cluster setup and you have `./clusters/{YOUR_CLUSTER_NAME}/.charon/` folder.

```bash
./multi_cluster/cluster.sh start {YOUR_CLUSTER_NAME}
```

### Stop cluster

```bash
./multi_cluster/cluster.sh stop {YOUR_CLUSTER_NAME}
```

### Delete cluster

```bash
./multi_cluster/cluster.sh delete {YOUR_CLUSTER_NAME}
```

## Manage base node

Manage the EL + CL + Grafana containers.

### Start base node

```bash
./multi_cluster/base.sh start
```

### Stop base node

```bash
./multi_cluster/base.sh stop
```
