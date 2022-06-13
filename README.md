![Obol Logo](https://obol.tech/obolnetwork.png)

<h1 align="center">Distributed Validator Charon Node with Docker Compose</h1>

This repo contains a [charon](https://github.com/ObolNetwork/charon) distributed validator node running using [docker-compose](https://docs.docker.com/compose/).

This repo aims to give users ability to participate in a [Distributed Validator Cluster](https://docs.obol.tech/docs/int/key-concepts#distributed-validator-cluster) by spinning up a charon node with a Validator Client.

## Quickstart

Ensure you have [docker](https://docs.docker.com/engine/install/) and [git](https://git-scm.com/downloads) installed. Also, make sure `docker` is running before executing the commands below.

```sh
# Clone this repo
git clone git@github.com:ObolNetwork/charon-distributed-validator-node.git

# Change directory
cd charon-distributed-validator-node

# Prepare an environment variable file (requires at minimum an Infura API endpoint for your chosen chain)
cp .env.sample .env

# Replace DATA_DIR environment variable in .env with the location of your cluster-lock.json, charon-enr-private-key and validator_keys

# Spin up a Distributed Validator Node with a Validator Client
docker-compose up

# Open Grafana dashboard
open http://localhost:3000/d/laEp8vupp

# Open Jaeger dashboard
open http://localhost:16686

# Deletes previously created distributed validator node
docker-compose down

```

## Project Status

It is still early days for the Obol Network and everything is under active development. 
It is NOT ready for mainnet. 
Keep checking in for updates, [here](https://github.com/ObolNetwork/charon/#supported-consensus-layer-clients) is the latest on charon's supported clients and duties.

## Validator Clients

### Teku

```
Keystore file /opt/charon/keys/keystore-0.json.lock already in use.
```

This can happen when you recreate a docker cluster with the same cluster files. Delete all `.charon/cluster/node<teku-vc-index-here>/keystore-*.json.lock` files to fix this. 

```
java.util.concurrent.CompletionException: java.lang.RuntimeException: Unexpected response from Beacon Node API (url = http://node1:16002/eth/v1/beacon/states/head/validators?id=0x8c4758687121c3b35203c69925e8056799369e0dac2c31c9984946436f3041821080a58e6c1a813b4de1007333552347, status = 404)
```

This indicates your validator is probably not activated yet.