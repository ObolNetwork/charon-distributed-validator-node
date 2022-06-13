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

# Create your charon ENR private key, this will create charon-enr-private-key in .charon directory
docker run --rm -v "$(pwd):/opt/charon" ghcr.io/obolnetwork/charon:latest create enr

# Set ENRs of all the operators participating in DKG ceremony in .env file corresponding to CHARON_OPERATOR_ENRS

# Create .charon/cluster-definition.json to participate in DKG ceremony
docker run --rm -v "$(pwd):/opt/charon" --env-file .env ghcr.io/obolnetwork/charon:latest create dkg

# Participate in DKG ceremony, this will create .charon/cluster-lock.json, .charon/deposit-data.json and .charon/validator_keys
docker run --rm -v "$(pwd):/opt/charon" ghcr.io/obolnetwork/charon:latest dkg

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
