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

In the `examples/` directory, you will find a collection of docker compose configuration files that demonstrate various clients and 
their configurations for running a Distributed Validator Node. These files are with filenames as {EC}-{CC}-{VC}.yml (where
EC: Execution Client, CC: Consensus Client, VC: Validator Client). For example,
if you wish to run a DV node with Nethermind EL, Teku CL and Lighthouse VC, you can run `nethermind_teku_lighthouse.yml`.

⚠️⚠️⚠️ **Important:**
The configurations provided in the examples are meant for demonstration purposes only and may not be suitable for production environments.
These examples are primarily intended for advanced users who are familiar with Docker and have a good understanding of execution and consensus clients.
Please exercise caution when using them and ensure that you thoroughly review and customize the configurations according to your specific requirements.

To run any of the examples, use the following command:

```
docker compose --env-file ./.env -f examples/geth_teku_lighthouse.yml up
```


# Project Status

It is still early days for the Obol Network and everything is under active development.
It is NOT ready for mainnet.
Keep checking in for updates, [here](https://dvt.obol.tech/) is the latest on charon's supported clients and duties.

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/faq/errors)
