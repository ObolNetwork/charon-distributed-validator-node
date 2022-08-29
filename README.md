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
git clone https://github.com/ObolNetwork/charon-distributed-validator-node.git

# Change directory
cd charon-distributed-validator-node

# Create your charon ENR private key, this will create a charon-enr-private-key file in the .charon directory
docker run --rm -v "$(pwd):/opt/charon" obolnetwork/charon:v0.9.0 create enr
```

You should expect to see a console output like

    Created ENR private key: .charon/charon-enr-private-key
    enr:-JG4QGQpV4qYe32QFUAbY1UyGNtNcrVMip83cvJRhw1brMslPeyELIz3q6dsZ7GblVaCjL_8FKQhF6Syg-O_kIWztimGAYHY5EvPgmlkgnY0gmlwhH8AAAGJc2VjcDI1NmsxoQKzMe_GFPpSqtnYl-mJr8uZAUtmkqccsAx7ojGmFy-FY4N0Y3CCDhqDdWRwgg4u

> ⚠️ Attention
>
> Please make sure to create a backup of the private key at `.charon/charon-enr-private-key`. Be careful not to commit it to git! **If you lose this file you won't be able to take part in the DKG ceremony.**

If you are taking part in an organised Obol testnet, submit the created ENR public address (the console output starting with `enr:-...` not the contents of the private key file) to the appropriate typeform.

## Step 2. Leader creates the DKG configuration file and distributes it to everyone else

One person, in the cluster or otherwise, will prepare the configuration file for the distributed key generation ceremony using the `charon create dkg` command. For the official Obol testnets, this step will be completed by an Obol core team member or the cluster captain and the definition file will be distributed to the cluster members for DKG completion.

In future, step 1 and step 2 of this guide will use the [Obol Distributed Validator Launchpad](https://docs.obol.tech/docs/dvk/distributed_validator_launchpad) to facilitate and verify these files are created in an authenticated manner.

```
# Prepare an environment variable file
cp .env.sample .env

# Set the ENRs of all the operators participating in the DKG ceremony in the .env file variable CHARON_OPERATOR_ENRS

# Set FEE_RECIPIENT_ADDRESS and WITHDRAWAL_ADDRESS to ETH1 addresses of your choice.
# NAME can be any random string like "Obol Team"
docker run --rm -v "$(pwd):/opt/charon" --env-file .env obolnetwork/charon:v0.9.0 create dkg --name=$NAME --fee-recipient-address=$FEE_RECIPIENT_ADDRESS --withdrawal-address=$WITHDRAWAL_ADDRESS

# The above command prepares a DKG configuration file.
```

This command should output a file at `.charon/cluster-definition.json`. This file needs to be shared with the other operators in a cluster.

## Step 3. Run the DKG

After receiving the `cluster-definition.json` file created by the leader, cluster members should ideally save it in the `.charon/` folder that was created during step 1, alternatively the `--definition-file` flag can override the default expected location for this file.

Every cluster member then participates in the DKG ceremony. For Charon v1, this needs to happen synchronously between participants at an agreed time.

```
# Participate in DKG ceremony, this will create .charon/cluster-lock.json, .charon/deposit-data.json and .charon/validator_keys
docker run --rm -v "$(pwd):/opt/charon" obolnetwork/charon:v0.9.0 dkg --p2p-bootnode-relay
```

Assuming the DKG is successful, a number of artefacts will be created in the `.charon` folder. These include:

- A `deposit-data.json` file. This contains the information needed to activate the validator on the Ethereum network.
- A `cluster-lock.json` file. This contains the information needed by charon to operate the distributed validator cluster with its peers.
- A `validator_keys/` folder. This folder contains the private key shares and passwords for the created distributed validators.

At this point you should make a backup of the `.charon/validator_keys` folder as replacing lost private keys is not straightforward at this point in charon's development. The `cluster-lock` and `deposit-data` files are identical for each operator and can be copied if lost.

If taking part in the official Athena testnet, one cluster member will have to submit the `cluster-lock` and `deposit-data` files to the Obol Team, setting the stage for activation.

## Step 4. Start the Distributed Validator Cluster

With the DKG ceremony over, the last phase before activation is to prepare your node for validating over the long term. This repo is configured to sync an execution layer client (`geth`) and a consensus layer client (`lighthouse`).

Before completing these instructions, you should assign a static local IP address to your device (extending the DHCP reservation indefinitely or removing the device from the DCHP pool entirely if you prefer), and port forward the TCP protocol on the public port `:3610` on your router to your device's local IP address on the same port. This step is different for every person's home internet, and can be complicated by the presence of dynamic public IP addresses. We are currently working on making this as easy as possible, but for the time being, a distributed validator cluster isn't going to work very resiliently if all charon nodes cannot talk directly to one another and instead need to have an intermediary node forwarding traffic to them.

**Caution**: If you manually update `docker-compose` to mount `lighthouse` from your locally synced `~/.lighthouse`, the whole chain database may get deleted. It'd be best not to manually update as `lighthouse` checkpoint-syncs so the syncing doesn't take much time.

**NOTE**: If you have a `geth` node already synced, you can simply copy over the directory. For ex: `cp -r ~/.ethereum/goerli data/geth`. This makes everything faster since you start from a synced geth node.

```
# Delete lighthouse data if it exists
rm -r ./data/lighthouse

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

# Other Actions

The above steps should get you running a distributed validator cluster. The following are some extra steps you may want to take either to help Obol with their testing program, or to improve the resilience and performance of your distributed validator cluster.

## Step 6. Leader Adds Central Monitoring Token

The cluster leader will be provided with a Central Monitoring Token used to push distributed validator metrics to our central prometheus service to monitor, analyze and improve your cluster's performance. The token needs to be added in prometheus/prometheus.yml replacing `$PROM_REMOTE_WRITE_TOKEN`. The token will look like:
`eyJtZXNzYWdlIjoiSldUIFJ1bGVzISIsImlhdCI6MTQ1OTQ0ODExOSwiZXhwIjoxNDU5NDU0NTE5fQ`. Final prometheus/prometheus.yml would look something like:

```
global:
  scrape_interval:     12s # Set the scrape interval to every 12 seconds. Default is every 1 minute.
  evaluation_interval: 12s # Evaluate rules every 12 seconds. The default is every 1 minute.

remote_write:
  - url: https://prometheus-prod-10-prod-us-central-0.grafana.net/api/prom/push
    authorization:
      credentials: 436764:eyJtZXNzYWdlIjoiSldUIFJ1bGVzISIsImlhdCI6MTQ1OTQ0ODExOSwiZXhwIjoxNDU5NDU0NTE5fQ
    name: obol-prom

scrape_configs:
  - job_name: 'charon'
    static_configs:
      - targets: ['charon:3620']
  - job_name: 'teku'
    static_configs:
      - targets: ['teku:8008']
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```
## Optional Step 7. Validator Voluntary Exit
   - A voluntary exit is when a validator chooses to stop performing its duties, and exits the beacon chain permanently. To voluntarily exit, the validator must continue performing its validator duties until successfully exited to avoid penalties.
   - To trigger a voluntary exit, a sidecar docker-compose command is executed that signs and submits the voluntary exit to the active running charon node that shares it with other nodes in the cluster. The commands below should be executed on the same machine and same folder as the active running charon-distribute-validator-node docker compose.
   - Note: Quorum peers in the cluster need to perform this task to exit a validator.
   - Create a new `exit_keys` folder next to `.charon/validator_keys`: `mkdir .charon/exit_keys`
   - Copy the validator keys and passwords that you want to exit from the `validator_keys` folder to the `exit_keys` folder.
     - E.g. to exit validator #4: `cp .charon/validator_keys/keystore/keystore-4* .charon/exit_keys/`
     - Warning: all keys copied to the `exit_keys` folder will be exited, so be careful!
   - Ensure the external network in `compose-volutary-exit.yml` is correct.
     - Confirm the name of the exiting `charon-distributed-validator-node` docker network: `docker network ls`.
     - If it isn't `charon-distributed-validator-node-dvnode`, then update `compose-volutary-exit.yml` accordingly.
   - Ensure the latest fork version epoch is used:
     - Voluntary exists require an epoch after which they take effect.
     - All VCs need to sign and submit the exact same messages (epoch) in DVT.
     - `--epoch=1` would be ideal, since all chains have that epoch in the past, so the validator should exit immediately.
     - There is however a [bug](https://github.com/sigp/lighthouse/issues/3471) in lighthouse requiring an epoch that maps to the latest fork version to be used.
     - `compose-volutary-exit.yml` is configured with `--epoch=112260` which is the latest Bellatrix fork on Prater.
     - If the Charon cluster is running on a different chain, **ALL** operators must update `--epoch` to the same latest fork version returned by `curl $BEACON_NODE/eth/v1/config/fork_schedule`.
   - Run the command to submit this node's partially signed voluntary exit:
     - `docker-compose -f compose-voluntary-exit.yml up`
     - Confirm the logs: `Exit for validator XXXXX submitted`
     - Exit the container: `Ctrl-C`
   - The charon metric `core_parsigdb_exit_total` will be incremented each time a voluntary exit partial signature is received, either from this node or from peers.
   - Once quorum partially signed voluntary exists have been received, they will be aggregated and submitted to the beacon node. This will add the validator to the beacon chain exit queue.
   - The validator keys can only be deleted from both `exit_keys` and `validator_keys` folders once the validator has successfully exited.

## Steps to host your own bootnode

If you are experiencing connectivity issues with the Obol hosted bootnode, or you want to improve your clusters latency and decentralisation, you can opt to host your own bootnode on a separate open and static internet port.

```
# Figure out your public IP
curl v4.ident.me

# Clone the repo and cd into it.
git clone https://github.com/ObolNetwork/charon-distributed-validator-node.git

cd charon-distributed-validator-node

# Replace 'replace.with.public.ip.or.hostname' in bootnode/docker-compose.yml with your public IPv4 or DNS hostname # Replace 'replace.with.public.ip.or.hostname' in bootnode/docker-compose.yml with your public IPv4 or DNS hostname

nano bootnode/docker-compose.yml

docker-compose -f bootnode/docker-compose.yml up
```

Test whether the bootnode is publicly accessible. This should return an ENR:
`curl http://replace.with.public.ip.or.hostname:3640/enr`

Ensure the ENR returned by the bootnode contains the correct public IP and port by decoding it with https://enr-viewer.com/.

Configure **ALL** charon nodes in your cluster to use this bootnode:

- Either by adding a flag: `--p2p-bootnodes=http://replace.with.public.ip.or.hostname:3640/enr`
- Or by setting the environment variable: `CHARON_P2P_BOOTNODES=http://replace.with.public.ip.or.hostname:3640/enr`

Note that a local `boonode/.charon/charon-enr-private-key` file will be created next to `bootnode/docker-compose.yml` to ensure a persisted bootnode ENR across restarts. 

# Project Status

It is still early days for the Obol Network and everything is under active development.
It is NOT ready for mainnet.
Keep checking in for updates, [here](https://github.com/ObolNetwork/charon/#supported-consensus-layer-clients) is the latest on charon's supported clients and duties.

# FAQs:
All operators should try to restart their node before attempting anything else as we are constantly releasing fixes. You can restart and update with the following:
```
docker-compose down
git pull
docker-compose up
```
You can check your logs using
`docker-compose logs --tail 100 -f`

<details open>
<summary><h2>ENR & Keys</h2></summary>
<details>
<summary><h4>How do I get my ENR if I want to generate it again?</h4></summary>
<ul>
<li><code>cd</code> to the directory where your private keys are located (ex: <code>cd /path/to/charon/enr/private/key</code>)</li>
<li>Run <code>docker run --rm -v "$(pwd):/opt/charon" obolnetwork/charon:latest enr</code>. This prints the ENR on your screen.</li>
<li>Please note that this ENR is not the same as the one generated when you created it for the first time. This is because the process of generating ENRs includes the current timestamp.</li>
</details>

<details>
    <summary><h4>What do I do if lose my <code>charon-enr-private-key</code>?</h4></summary>
<ul>
<li>For now, ENR rotation/replacement is not supported, it will be supported in a future release.</li>
<li>Therefore, it's advised to always keep a backup of your <code>private-key</code> in a secure location (ex: cloud storage, USB Flash drive etc.)</li>
</details>

<details>
<summary><h4>I can't find the keys anywhere.</h4></summary>
<ul>
<li>The <code>charon-enr-private-key</code> is generated inside a hidden folder <code>.charon</code>.</li>
<li>To view it, run <code>ls -al</code> in your terminal.</li>
<li>You can then copy the key to your <code>~/Downloads</code> folder for easy access by running <code>cp .charon/charon-enr-private-key ~/Downloads</code>. This step maybe a bit different for windows.</li>
<li>Else, if you are on <code>macOS</code>, press <code>Cmd + Shift + . </code> to view the <code>.charon</code> folder in the finder application.</li></ul>
</details>
</details>

<details open>
<summary><h2>Lighthouse</h2></summary>
<details>
<summary><h4>Downloading historical blocks</h4></summary>
This means that Lighthouse is still syncing which will throw a lot of errors down the line. Wait for the sync before moving further.
</details>

<details>
<summary><h4><code>Failed to request attester duties</code> error</h4></summary>
Indicates there is something wrong with your lighthouse beacon node.
<br><br>
This might be because the request buffer is full as your node is never starting consensus since it never gets the duties.
</details>

<details>
<summary><h4><code>Not enough time for a discovery seach</code> error</h4></summary>
This could be linked to a internet connection being to slow or relying on a slow third-party service such as Infura.
</details>
</details>

<details open>
<summary><h2>Beacon Node</h2></summary>
<details>
<summary><h4><code>Error communicating with Beacon Node API</code> & <code>Error while connecting to beacon node event stream</code></h4></summary>
This is likely due to lighthouse not done syncing, wait and try again once synced.
<br><br>
Can also be linked to <a href="https://github.com/ObolNetwork/charon-distributed-validator-node#teku-keystore-file-error">Teku keystore issue</a>.
</details>

<details>
<summary><h4>Clock sync issues</h4></summary>
Either your clock server time is off, or you are talking to a remote beacon client that is super slow (this is why we advise against using services like infura).
</details>

<details>
<summary><h4>My beacon node API is flaky with lots of errors and timeouts</h4></summary>
A good quality beacon node API is critical to validator performance. It is always advised to run your own beacon node to ensure low latencies to boost validator performance. 
<br><br>
Using 3rd party services like Infura's beacon node API has significant disadvantages since the quality is often low. Requests often return 500s or timeout (Charon times out after 2s). This results in lots of warnings and errors and failed duties. 
<br><br>
We are working on https://github.com/ObolNetwork/charon/issues/960 to mitigate against this, but running a local beacon node is still always preferred. We are not yet considering increasing the 2s timeout since that can have knock-on effects.
</details>

</details>

<details open>
<summary><h2>Charon</h2></summary>
<details>
<summary><h4><code>Attester failed in consensus component</code> error</h4></summary>
The required number of operators defined in your cluster-lock file is probably not online to sign successfully. Make sure all operators are running the latest version of charon.
<br><br>
To check if some peers are not online:
<br>
<code>docker logs charon-distributed-validator-node-charon-1 2>&1 | grep 'absent'</code>
</details>

<details>
<summary><h4><code>Attester failed in parSigDBThreshold component</code> error</h4></summary>
Should be fixed in the latest version of Charon, upgrade and restart your node.
</details>

<details>
<summary><h4><code>Peer connection failing and dropping</code> error</h4></summary>
Should be fixed in the latest version of Charon, upgrade and restart your node. Likely linked to Obol bootnode infrastructure. You can also try to <a href="https://github.com/ObolNetwork/charon-distributed-validator-node#steps-to-host-your-own-bootnode">run your own bootnode</a>.
</details>

<details>
<summary><h4><code>Load private key</code> error</h4></summary>
Make sure you have successfully run a DKG before running the node. The key should be created and placed in the right directory during the ceremony
<br><br>
Also, make sure you are working in the right directory: <code>charon-distributed-validator-node</code>
</details>

<details>
<summary><h4><code>Failed to confirm node connection</code> error</h4></summary>
Wait for Teku & Lighthouse sync to be complete.
</details>

<details>
<summary><h4><code>Reserve relay circuit: reservation failed</code> error</h4></summary>
<code>RESERVATION_REFUSED</code> is returned by the bootnode libp2p relay when some maximum limit has been reached. 
<br><br>
This is most often due to "maximum reservations per IP/peer". This is when your charon node is restarting or in some error loop and constantly attempting to create new relay reservations reaching the maximum. To fix this error, stop your charon node for 30mins before restarting it. This should allow the bootnode enough time to reset your ip/peer limits and should then allow new reservations.
<br><br>
This could also be due to the bootnode being overloaded in general, so reaching a server wide "maximum connections" limit. This is an issue with bootnode scalability and we are working in a long term fix for this. If stopping your node for 30min doesn't solve <code>RESERVATION_REFUSED</code>, then it is a problem the Obol team needs to solve.
</details>
</details>

<details open>
<summary><h2>Teku</h2></summary>
<details>
<summary><h4>Teku <code>keystore file</code> error</h4></summary>
Teku sometimes logs an error which looks like <code>Keystore file /opt/charon/validator_keys/keystore-0.json.lock already in use.</code>
<br><br>This can be solved by deleting the file(s) ending with <code>.lock</code> in the folder <code>.charon/validator_keys</code>.
<br><br>It is caused by an unsafe shut down of Teku (usually by double pressing Ctrl+C to shutdown containers faster).
</details>
</details>

<details open>
<summary><h2>Grafana</h2></summary>
<details>
<summary><h4>How to fix the grafana dashboard?</h4></summary>
Sometimes, grafana dashboard doesn't load any data first time around.You can solve this by following the steps below:
<ul>
<li>Click the Wheel Icon > Datasources</li>
<li>Click prometheus</li>
<li>Change the "Access" field from <code>Server (default)</code> to <code>Browser</code>. Press "Save & Test". It should fail.</li>
<li>Change the "Access" field back to <code>Server (default)</code> and press "Save & Test". You should be presented with a green success icon saying "Data source is working" and you can return to the dashboard page.</li>
</ul>
</details>

<details>
<summary><h4><code>N/A</code> & <code>No data</code> in validator info panel</h4></summary>
Can be linked to the <a href="https://github.com/ObolNetwork/charon-distributed-validator-node#teku-keystore-file-error">Teku Keystore issue</a>.
</details>
</details>

<details open>
<summary><h2>Prometheus</h2></summary>
<details>
<summary><h4><code>Unauthorized: authentication error: invalid token</code></h4></summary>
Get the monitoring token and following <a href"https://github.com/ObolNetwork/charon-distributed-validator-node#step-6-leader-adds-central-monitoring-token">Step 6 of the quickstart</a>. This is not mandatory and should not prevent the cluster from running. Only the cluster captain/leader should do this step and resolve this error.
<br><br>
Check <a href="https://discord.com/channels/849256203614945310/1003921582965674104/1005569855698768066">these instructions</a> from our Discord to get the monitoring token.
</details>

</details>

<details open>
<summary><h2>Docker</h2></summary>
<details>
<summary><h4>How to fix <code>permission denied</code> errors?</h4></summary>
Permission denied errors can come up in a variety of manners, particularly on Linux and WSL for Windows systems. In the interest of security, the charon docker image runs as a non-root user, and this user often does not have the permissions to write in the directory you have checked out the code to. This can be generally be fixed with some of the following:
<ul>
<li>Running docker commands with <code>sudo</code>, if you haven't <a href= "https://docs.docker.com/engine/install/linux-postinstall/">setup docker to be run as a non-root user</a>.</li>
<li>Changing the permissions of the <code>.charon</code> folder with the commands:</li>
<ul>
<li><code>mkdir .charon</code> (if it doesn't already exist)</li>
<li><code>sudo chmod -R 666 .charon</code></li>
</ul></ul>
</details>

<details>
<summary><h4>I see a lot of errors after running <code>docker-compose up</code></h4></summary>
It's because both geth and lighthouse start syncing and so there's connectivity issues among the containers. Simply let the containers run for a while. You won't observe frequent errors when geth finishes syncing. 
<br><br>
You can also add a second beacon node endpoint for something like infura by adding a comma separated API URL to the end of <code>CHARON_BEACON_NODE_ENDPOINTS</code> in the docker-compose(./docker-compose.yml#84).
</details>

</details>

<details open>
<summary><h2>Standalone Bootnode</h2></summary>
<details>
<summary><h4><code>Resolve IP of p2p external host flag: lookup replace.with.public.ip.or.hostname: no such host</code> error</h4></summary>
Replace <code>replace.with.public.ip.or.hostname</code> in the bootnode/docker-compose.yml with your real public IP or DNS hostname.
</details>

</details>
