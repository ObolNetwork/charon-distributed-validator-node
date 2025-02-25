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

To customize your node configuration, you can create a `docker-compose.override.yml` file. A sample override file is provided as `docker-compose.override.yml.sample` which you can use as a starting point. This allows you to override default settings and choose different client combinations without modifying the base configuration.

⚠️⚠️⚠️ **Important:**
The configurations provided are meant for demonstration purposes only and may not be suitable for production environments.
Please exercise caution when using them and ensure that you thoroughly review and customize the configurations according to your specific requirements.

To run the default configuration, use the following command:

```sh
docker compose up
```

To use a custom configuration with an override file:

1. Copy the sample override file:
```sh
cp docker-compose.override.yml.sample docker-compose.override.yml
```

2. Edit the `docker-compose.override.yml` file to suit your needs

3. Run docker compose (it will automatically use both files):
```sh
docker compose up
```

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.tech/docs/faq/errors)
