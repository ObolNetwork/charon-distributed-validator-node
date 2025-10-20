![Obol Logo](https://obol.tech/obolnetwork.png)

<h1 align="center">Lido Charon Distributed Validator Node (LCDVN)</h1>

This repo contains the [docker-compose](https://docs.docker.com/compose/) files needed to run one node in a [charon](https://github.com/ObolNetwork/charon) [Distributed Validator Cluster](https://docs.obol.tech/docs/int/key-concepts#distributed-validator-cluster) for a Lido Simple DVT module.

A distributed validator node is a machine running:

- An Ethereum Execution client
- An Ethereum Consensus client
- An Ethereum Distributed Validator client
- An Ethereum Validator client

![Distributed Validator Node](DVNode.png)

# Getting Started

**`lido-charon-distributed-validator-node` is a repo intended as a _deployment guide_ and is not intended to be the canonical way to deploy a distributed validator.**

**Operators are encouraged to use this repository to build and maintain their own configurations that work for their individual use case.**


Check the Obol [docs](https://docs.obol.tech/docs/start/quickstart_group) for detailed instructions on how to get started using example repos. 

To configure this repo for a particular network, follow these instructions. If you do not, your node will fail to start. 

1. Copy `.env.sample.<network-name>` to `.env`:

```sh
    # mainnet
    cp .env.sample.mainnet .env

    # holesky
    cp .env.sample.holesky .env

    # hoodi
    cp .env.sample.hoodi .env
```

> **_NOTE:_** If you are using commit-boost, instead of mev-boost, do the same for commit-boost's config:

```sh
    # mainnet
    cp commit-boost/.config.toml.sample.mainnet commit-boost/config.toml

    # holesky
    cp commit-boost/.config.toml.sample.holesky commit-boost/config.toml

    # hoodi
    cp commit-boost/.config.toml.sample.hoodi commit-boost/config.toml
```

2. Grab your operator ID from the lido [mainnet dashboard](https://operators.lido.fi/) or [testnet dashboard](https://operators-holesky.testnet.fi/).
3. Find `VE_OPERATOR_ID` in `.env` and set it to your operator ID.
4. Find `VE_EASY_TRACK_MOTION_CREATOR_ADDRESSES_ALLOWLIST=["0xYourNodeOperatorRewardAddress"]`, uncomment it, and change `0xYourNodeOperatorRewardAddress` to your Lido Operator SAFE manager address for your cluster.
5. To enable log collection with promtail which will stream logs to the Obol Core team to help identify cluster issues find `MONITORING=${MONITORING:-monitoring},monitoring-log-collector` and uncomment it.
6. Save and close `.env`.

You will need a `.charon/` folder from a completed DKG present to complete the setup of this repo.

Finally, to run the cluster run one of the following commands.

```sh
docker compose up -d
```

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/faq/errors).
