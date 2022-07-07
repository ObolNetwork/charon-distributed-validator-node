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

The following instructions aim to assist a group of users coordinating together to create a distributed validator cluster between them. Only one person needs to do [step 2](#step-2-leader-creates-the-dkg-configuration-file-and-distributes-it-to-everyone-else) and [step 5](#step-5-activate-the-deposit-data) in the quickstart process.

## Pre-requisites

Ensure you have [docker](https://docs.docker.com/engine/install/) and [git](https://git-scm.com/downloads) installed. Also, make sure `docker` is running before executing the commands below.

## Step 1. Creating and backing up a private key for charon

The first step of running a cluster is preparing for a distributed key generation ceremony. To do this everyone must create an [ENR](https://docs.obol.tech/docs/int/faq#what-is-an-enr) for their charon client. This ENR is a public/private key pair, and allows the other charon clients in the DKG to identify and connect to your node.

```sh
# Clone this repo
git clone git@github.com:ObolNetwork/charon-distributed-validator-node.git

# Change directory
cd charon-distributed-validator-node

# Create your charon ENR private key, this will create a charon-enr-private-key file in the .charon directory
docker run --rm -v "$(pwd):/opt/charon" ghcr.io/obolnetwork/charon:v0.8.0 create enr
```

You should expect to see a console output like

    Created ENR private key: .charon/charon-enr-private-key
    enr:-JG4QGQpV4qYe32QFUAbY1UyGNtNcrVMip83cvJRhw1brMslPeyELIz3q6dsZ7GblVaCjL_8FKQhF6Syg-O_kIWztimGAYHY5EvPgmlkgnY0gmlwhH8AAAGJc2VjcDI1NmsxoQKzMe_GFPpSqtnYl-mJr8uZAUtmkqccsAx7ojGmFy-FY4N0Y3CCDhqDdWRwgg4u

Please make sure to make a backup of the private key at `.charon/charon-enr-private-key`. Be careful not to commit it to git! If you lose this file you won't be able to take part in the DKG ceremony.

If you are taking part in an organised Obol testnet, submit the created ENR public address (the console output starting with `enr:-...` not the contents of the private key file) to the appropriate typeform.

## Step 2. Leader creates the DKG configuration file and distributes it to everyone else

One person, in the cluster or otherwise, will prepare the configuration file for the distributed key generation ceremony using the `charon create dkg` command. For the official Obol testnets, this step will be completed by an Obol core team member and the definition file will be distributed to the testnet team for DKG completion. 

In future, step 1 and step 2 of this guide will use the [Obol Distributed Validator Launchpad](https://docs.obol.tech/docs/dvk/distributed_validator_launchpad) to facilitate and verify these files are created in an authenticated manner.

```
# Prepare an environment variable file 
cp .env.sample .env

# Set the ENRs of all the operators participating in the DKG ceremony in the .env file variable CHARON_OPERATOR_ENRS

# Prepare a DKG configuration file by running the following
docker run --rm -v "$(pwd):/opt/charon" --env-file .env ghcr.io/obolnetwork/charon:v0.8.0 create dkg

```

This command should output a file at `.charon/cluster-definition.json`. This file needs to be shared with the other operators in a cluster. 

## Step 3. Run the DKG

After receiving the `cluster-definition.json` file created by the leader, it should ideally be saved in the `.charon/` folder that was created during step 1, alternatively, the `--definition-file` flag can override the default expected location for this file. 

```
# Participate in DKG ceremony, this will create .charon/cluster-lock.json, .charon/deposit-data.json and .charon/validator_keys
docker run --rm -v "$(pwd):/opt/charon" ghcr.io/obolnetwork/charon:v0.8.0 dkg

```

Assuming the DKG is successful, a number of artefacts will be created in the `.charon` folder. These include:

- A `deposit-data.json` file. This contains the information needed to activate the validator on the Ethereum network.
- A `cluster-lock.json` file. This contains the information needed by charon to operate the distributed validator cluster with its peers. 
- A `validator_keys/` folder. This folder contains the private key shares and passwords for the created distributed validators.

At this point you should make a backup of the `.charon/validator_keys` folder.  Replacing lost private keys is not straightforward at this point in charon's development. The `cluster-lock` and `deposit-data` files are identical for each operator and can be copied if lost. 

## Step 4. Start the Distributed Validator Cluster

With the DKG ceremony over, the last phase before activation is to prepare your node for validating over the long term. Currently this repo assumes you will use a beacon node provided by Infura or another cloud provider, but in future this repo will be configured to sync a beacon client locally in docker-compose. 

Before completing these instructions, you should assign a static local IP address to your device (extending the DHCP reservation indefinitely or removing the device from the DCHP pool entirely if you prefer), and port forward the TCP protocol on the public port `:3610` on your router to your device's local IP address on the same port. This step is different for every person's home internet, and can be complicated by the presence of dynamic public IP addresses. We are currently working on making this as easy as possible, but for the time being, a distributed validator cluster isn't going to work very resiliently if all charon nodes cannot talk directly to one another and instead need to have an intermediary node forwarding traffic to them. 

```
# Prepare an environment variable file (requires at minimum an Infura API endpoint for your chosen chain set as CHARON_BEACON_NODE_ENDPOINT)
cp .env.sample .env

# Spin up a Distributed Validator Node with a Validator Client
docker-compose up

# Open Grafana dashboard
open http://localhost:3000/d/singlenode/
```

You should use the grafana dashboard to infer whether your cluster is healthy. In particular you should check:

- That your charon client can connect to the configured beacon client.
- That your charon client can connect to all peers

You might notice that there are logs indicating that a validator cannot be found and that APIs are returning 404. This is to be expected at this point, as the validator public keys listed in the lock file have not been deposited and acknowledged on the consensus layer yet (usually ~16 hours after the deposit is made).

To turn off your node after checking the health of the cluster you can run:

```
# Shut down the currently running distributed validator node
docker-compose down
```

## Step 5. Activate the deposit data

If you and your team have gotten to this phase of the quickstart, and you have successfully created a distributed validator together, and you have connected all of your charon clients together such that the monitoring indicates that they are all healthy and ready to operate, one person may process to activate this deposit data with the existing [staking launchpad](https://prater.launchpad.ethereum.org/).

This process can take a minimum of 16 hours, with the maximum time to activation being dictated by the length of the activation queue, which can be weeks. You can leave your distributed validator cluster offline until closer to the activation period if you would prefer. You can also use this time to improve and harden your monitoring and alerting for the cluster. 

If you have gotten this far through the process, and whether you succeed or fail at running the distributed validator successfully on the testnet, we would like to hear your feedback on the process and where you encountered difficulties. Please open issues in either this repo if the problem is deployment related, or the [charon](https://github.com/ObolNetwork/charon) repo if the issue is directly related to the client. 

Thanks for trying our quickstart guide!

# Project Status

It is still early days for the Obol Network and everything is under active development.
It is NOT ready for mainnet.
Keep checking in for updates, [here](https://github.com/ObolNetwork/charon/#supported-consensus-layer-clients) is the latest on charon's supported clients and duties.

## Bugs, Logs and Gotchas

The following are some common issues that arise using this repo and how to fix them.

### Teku doesn't start due to a locked private key

    Keystore file /opt/charon/validator_keys/keystore-0.json.lock already in use.

- Delete the file(s) ending with `.lock` in the folder `.charon/validator_keys`. Caused by an unsafe shut down of Teku (usually by double pressing Ctrl+C to shutdown containers faster).

### Grafana doesn't load any data

- Sometimes the grafana dashboard doesn't load any data first time around.
- Click the Wheel Icon > Datasources
- Click prometheus
- Change the "Access" field from `Server (default)` to `Browser`. Press "Save & Test". It should fail.
- Change the "Access" field back to `Server (default)` and press "Save & Test". You should be presented with a green success icon saying "Data source is working" and you can return to the dashboard page.

### Permission denied errors

Permission denied errors can come up in a variety of manners, particularly on Linux and WSL for Windows systems. In the interest of security, the charon docker image runs as a non-root user, and this user often does not have the permissions to write in the directory you have checked out the code to.

This can be generally be fixed with some of the following:

- Running docker commands with `sudo`, if you haven't [setup docker to be run as a non-root](https://docs.docker.com/engine/install/linux-postinstall/) user.
- Changing the permissions of the `.charon` folder with the commands:
  - `mkdir .charon` (if it doesn't already exist)
  - `sudo chmod -R 666 .charon`
