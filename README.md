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

Check the Obol [docs](https://docs.obol.tech/docs/int/quickstart) for detailed instructions on how to get started using this repo.

While the quick-start guide linked above is adequate for general-purpose deployments, this repository needs further setup for mainnet deployment:

1. Copy `.env.sample.mainnet` to `.env`:
    ```sh
    cp .env.sample.mainnet .env
    ```
2. Grab your operator ID from the [lido dashboard](https://operators.lido.fi/)
3. Find `VE_OPERATOR_ID` in `.env` and set it to your operator ID
4. Save and close `.env`

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/int/faq/errors)
