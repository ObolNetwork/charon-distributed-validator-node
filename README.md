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
