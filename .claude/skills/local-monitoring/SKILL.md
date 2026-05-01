---
name: local-monitoring
description: Query the local Grafana/Prometheus/Loki stack shipped with this CDVN repo. Use when investigating cluster health, charon/beacon/EL errors, peer connectivity, validator performance, or log patterns against the locally-running monitoring stack (not Obol's hosted Grafana).
user-invokable: true
---

# Local Monitoring

Query the local monitoring stack (Grafana, Prometheus, Loki) that ships with this repo to investigate cluster health and diagnose issues.

For Obol's hosted Grafana (across all clusters), use the `obol-monitoring` skill instead. This skill is for the local stack only.

## Prerequisites

Before running, verify:
1. The monitoring stack is up: `docker compose ps prometheus grafana loki` shows them running
2. Grafana is reachable on the host at `http://localhost:${MONITORING_PORT_GRAFANA:-3000}` (default 3000)
3. The user knows their Grafana admin credentials, or has unauthenticated access enabled (default in this repo's `grafana.ini`)

If the stack isn't up, point the user to `docker compose up -d prometheus grafana loki` first.

## Architecture notes

- **Prometheus** (`:9090`) and **Loki** (`:3100`) are on the docker network only — not exposed to the host by default. Query them through one of:
  - **Grafana datasource proxy** (preferred): `http://localhost:3000/api/datasources/proxy/uid/<prometheus|loki>/<path>` — uses Grafana's own connection
  - **`docker compose exec`** fallback: `docker compose exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=...'`
- Datasource UIDs (from `grafana/datasource.yml`): `prometheus`, `loki`, `tempo`
- Charon metrics are labeled with `cluster_name` and `cluster_peer` — get these from `.env` (`CLUSTER_NAME`, `CLUSTER_PEER`) before querying

## Gather Arguments

Use AskUserQuestion to clarify what the user wants to investigate. Common shapes:

1. **What to investigate** — pick one:
   - Cluster health snapshot (readyz, peers, active validators)
   - Charon error/log search (last N minutes)
   - Beacon node performance (latency, sync status)
   - Peer connectivity (ping latency, connection types)
   - Custom PromQL / LogQL query
2. **Time range** — default last 15m; ask if investigating a specific incident
3. **Cluster scope** — usually their own (`$CLUSTER_NAME` from `.env`); ask only if multiple clusters share this Prometheus

If the request is already specific (e.g. "show me charon errors from the last hour"), skip AskUserQuestion and proceed.

## Execution

### Instant query (Prometheus)

```bash
GRAFANA_URL="http://localhost:${MONITORING_PORT_GRAFANA:-3000}"
curl -sG "$GRAFANA_URL/api/datasources/proxy/uid/prometheus/api/v1/query" \
  --data-urlencode 'query=<PROMQL>'
```

### Range query (Prometheus)

```bash
curl -sG "$GRAFANA_URL/api/datasources/proxy/uid/prometheus/api/v1/query_range" \
  --data-urlencode 'query=<PROMQL>' \
  --data-urlencode "start=$(date -u -v-15M +%s)" \
  --data-urlencode "end=$(date -u +%s)" \
  --data-urlencode 'step=30s'
```

### Log search (Loki)

```bash
curl -sG "$GRAFANA_URL/api/datasources/proxy/uid/loki/loki/api/v1/query_range" \
  --data-urlencode 'query={service_name="charon"} |= "error"' \
  --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" \
  --data-urlencode 'limit=200'
```

### Fallback via `docker compose exec`

If the Grafana proxy is unavailable:
```bash
docker compose exec prometheus wget -qO- "http://localhost:9090/api/v1/query?query=<URL_ENCODED_PROMQL>"
docker compose exec loki      wget -qO- "http://localhost:3100/loki/api/v1/query_range?query=<...>"
```

For a query cookbook (cluster health, charon errors, peer ping, BN latency, validator effectiveness), see [queries.md](queries.md).

## Output handling

Parse the JSON response and present results clearly:

- **Prometheus instant query** — show metric labels + value, flag anomalies (zeros where non-zero expected, threshold breaches)
- **Prometheus range query** — summarise min/max/avg over the window; call out spikes
- **Loki logs** — group by `cluster_peer` if present; surface error/warn lines verbatim with timestamps; suppress repetitive noise
- Always print the **exact query that was run** so the user can re-run it in Grafana

If the response contains `"status":"error"`, surface the `error` and `errorType` fields and stop — do not invent results.

## Common diagnoses

When showing results, watch for these patterns and call them out:

- **`app_monitoring_readyz != 1`** — node is not ready; explain what readyz state means (1=ready, other=various failure modes documented in charon docs)
- **High `p2p_ping_latency_secs` p90** — peer network is slow; check `p2p_peer_connection_types` for relayed vs direct
- **`p2p_ping_success == 0`** for a peer — that operator is unreachable
- **Charon log `error` spikes** — group by `topic` / `component` to identify which subsystem
- **`core_scheduler_validators_active` lower than `cluster_validators`** — some validators not active (not yet activated, or exited)
- **EL/CL container missing from metrics** — check `docker compose ps` and respective container logs

## Pointers to dashboards

Direct the user to the pre-provisioned dashboards in `grafana/dashboards/` rather than reinventing them:
- `charon_overview_dashboard.json` — readyz, peers, validator activity (start here)
- `cluster_dashboard.json` — full cluster view across operators
- `node_overview_dashboard.json` — host/EL/CL/VC resource usage
- `logs_dashboard.json` — Loki log explorer with charon filters

Open in browser: `http://localhost:${MONITORING_PORT_GRAFANA:-3000}/dashboards`.

## Dependencies

- `curl`, `jq` (for parsing responses cleanly)
- Running `prometheus`, `grafana`, `loki` containers from this compose stack
- `CLUSTER_NAME` and `CLUSTER_PEER` set in `.env` (used as Prometheus label values)
