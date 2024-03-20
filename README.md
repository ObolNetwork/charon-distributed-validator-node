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


Check the Obol [docs](https://docs.obol.tech/docs/start/quickstart_group) for detailed instructions on how to get started using this repo.

This repo is configured to run on holesky, and needs further setup for a mainnet deployment:

1. Copy `.env.sample.mainnet` to `.env`:
    ```sh
    cp .env.sample.mainnet .env
    ```
2. Grab your operator ID from the [lido dashboard](https://operators.lido.fi/).
3. Find `VE_OPERATOR_ID` in `.env` and set it to your operator ID.
4. Save and close `.env`.

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/int/faq/errors).
