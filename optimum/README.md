# Optimum Gateway (opt-in)

Adds an [Optimum Gateway](https://getoptimum.github.io/optimum-gateway/versions/latest/) container on the `dvnode` network so the consensus client can receive blocks earlier via Optimum's mesh. Charon, the validator client, and DV keys are unchanged.

Off by default: a CDVN that does not append `compose-optimum.yml` to `COMPOSE_FILE` is unmodified.

Partner API keys, `gateway_cluster_id`, and gateway config: [Gateway documentation](https://getoptimum.github.io/optimum-gateway/versions/latest/).

## Prerequisites

- Running CDVN with a beacon node (`CL` set to a `compose-cl.yml` service, e.g. `cl-lighthouse`).
- Optimum API key (`ogw_live_...`) and the `gateway_cluster_id` issued with that key.
- `curl` and `jq` on the host (for `init-optimum.sh`).

## Enable

From the CDVN root:

1. Add Optimum variables to `.env` (see [`.env.optimum.sample`](.env.optimum.sample)):

   ```sh
   OPT_API_KEY=ogw_live_...
   GATEWAY_CLUSTER_ID=...   # issued with the API key; not CLUSTER_NAME
   GATEWAY_VERSION=v1.1.1
   ```

2. Append `:compose-optimum.yml` to the existing `COMPOSE_FILE` line. Do not replace the list. Example:

   ```sh
   COMPOSE_FILE=compose-el.yml:compose-cl.yml:compose-vc.yml:compose-mev.yml:docker-compose.yml:compose-optimum.yml
   ```

3. Start the stack so the CL is up, then write the gateway config and start the gateway:

   ```sh
   docker compose up -d
   ./optimum/init-optimum.sh
   docker compose up -d optimum-gateway
   ```

`init-optimum.sh` reads `CL`, `CL_PORT_HTTP`, and `GATEWAY_CLUSTER_ID` from `.env`, calls `GET /eth/v1/node/identity`, and writes `optimum/config/app_conf.yml`.

No CL `command:` edits are required. The gateway is configured with the beacon node as a direct libp2p peer on `dvnode`.

## Verify

```sh
curl -s http://localhost:48123/health | jq '{status, checks: {cl_peers: .checks.cl_peers, mump2p_peers: .checks.mump2p_peers}}'

# Optional: confirm the CL lists the gateway peer
GW_PEER=$(curl -s http://localhost:48123/api/v1/self_info | jq -r '.peer_id')
curl -s "http://127.0.0.1:${CL_PORT_HTTP:-5052}/eth/v1/node/peers/${GW_PEER}" | jq '.data | {state, direction}'
```

When connected: `checks.cl_peers >= 1`.

## Disable

Remove `:compose-optimum.yml` from `COMPOSE_FILE` and run `docker compose up -d`. Stock CDVN behaviour is restored.

## Supported CL clients

| `CL` in `.env` | P2P port on `dvnode` |
| -------------- | -------------------- |
| `cl-lighthouse` | 9000 |
| `cl-lodestar` | 9000 |
| `cl-teku` | 9000 |
| `cl-nimbus` | 9000 |
| `cl-grandine` | 9000 |
| `cl-prysm` | 13000 (host map is still `CL_PORT_P2P`, default 9000) |

REST is `CL_PORT_HTTP` (default 5052) on all of the above. Set `CL` before running `init-optimum.sh`. Override the container P2P port with `CL_P2P_INTERNAL_PORT` only if you have changed `compose-cl.yml`.
