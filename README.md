![Obol Logo](https://obol.org/obolnetwork.png)

<h1 align="center">Charon Distributed Validator Node</h1>

This repo contains the [docker-compose](https://docs.docker.com/compose/) files needed to run one node in a [charon](https://github.com/ObolNetwork/charon) [Distributed Validator Cluster](https://docs.obol.org/docs/int/key-concepts#distributed-validator-cluster).

A distributed validator node is a machine running:

- An Ethereum Execution client
- An Ethereum Consensus client
- An Ethereum Distributed Validator client
- An Ethereum Validator client

![Distributed Validator Node](DVNode.png)

# Quickstart

Check the Obol [docs](https://docs.obol.org/docs/start/quickstart_overview) for detailed instructions on how to get started using this repo.

# Adding Validators

Starting with charon v1.6, you can add validators to your cluster using the `charon alpha add-validators` command. Note that this is an experimental feature and should not be used in production (Mainnet) yet. The example below is designed for the default configuration provided by this repository and assumes the stack uses the Lodestar validator client.

1. Review the `add-validators` command [CLI reference](https://docs.obol.org/next/learn/charon/charon-cli-reference).
2. Ensure this folder contains a valid `.charon` directory currently used by the running node. Keep the DV node running during the process.
3. Run the following command to collectively generate and add 10 new validators with other node operators (similar to DKG):

```sh
charon alpha add-validators --num-validators 10 --withdrawal-addresses=0x<your_withdrawal_address> --fee-recipient-addresses=0x<your_fee_recipient_address>
```

This command will create a new cluster configuration that includes both existing and new validators. It will also generate the necessary keys for the new validators and deposit-data files. The new configuration will be saved in the `.charon-add-validators` directory.

4. To start using the new configuration (with the added validators), stop the current charon and validator client instances:

```sh
docker compose stop charon lodestar
```

5. Back up and remove the existing `.charon` directory, then move the `.charon-add-validators` directory to `.charon`:

```sh
mv .charon .charon-backup
mv .charon-add-validators .charon
```

6. Restart the charon and validator client instances:

```sh
docker compose up -d charon lodestar
```

Lodestar's boot script (`lodestar/run.sh`) will automatically import all keys, removing any existing keys and cache. Charon will load the new `cluster-lock.json` and recognize all validators in the cluster.

Steps 4–6 must be performed independently by all node operators, likely at different times. During this process, some nodes will use the old configuration and others the new one. Once the number of upgraded nodes reaches the BFT threshold, the newly added validators will begin participating in the cluster.

## Current limitations:

- The new cluster configuration will not be reflected in Launchpad.
- The new cluster configuration will have a new cluster hash, so the observability stack will display new cluster data under a different identifier.
- The `add-validators` command supports the KeyManager API (similar to the `dkg` command), but since it does not have direct access to the keys, it cannot produce valid cluster lock signatures. In this case, you must use the `--unverified` flag, which produces empty signatures. This requires adding the `--no-verify` flag to the `charon run` command.
- If you use different validator clients, review the keys import script. The old keys in `.charon/validator_keys` remain unchanged, so verify that importing the same keys will not disrupt the validator client's state.

# FAQs

Check the Obol docs for frequent [errors and resolutions](https://docs.obol.org/docs/faq/errors)
