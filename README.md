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

While the quick-start guide linked above is adequate for general-purpose deployments, this repository needs further setup:

1. copy `.env.sample` to `.env`:
  ```sh
  cp .env.sample .env
  ```
2. grab your operator ID from [https://operators.lido.fi/](https://operators.lido.fi/)
3. find `VE_OPERATOR_ID` in `.env` and set it to your operator ID
4. save and close `.env`

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/int/faq/errors)
