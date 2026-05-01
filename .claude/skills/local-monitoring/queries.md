# Query Cookbook

Curated PromQL and LogQL examples for the local monitoring stack. All examples assume `cluster_name="$CLUSTER_NAME"` from `.env`. Substitute the real value before running.

## PromQL — Cluster health

```promql
# Is this node ready? 1 = ready, anything else = degraded.
app_monitoring_readyz{cluster_name="$CLUSTER_NAME"}

# Active validators on the local node
core_scheduler_validators_active{cluster_name="$CLUSTER_NAME"}

# Total validators in the cluster (from cluster-lock)
cluster_validators{cluster_name="$CLUSTER_NAME"}

# Operators and consensus threshold
cluster_operators{cluster_name="$CLUSTER_NAME"}
cluster_threshold{cluster_name="$CLUSTER_NAME"}
```

## PromQL — Peer connectivity

```promql
# Per-peer ping success in the last 5m (0 = peer unreachable)
sum by (cluster_peer, peer) (p2p_ping_success{cluster_name="$CLUSTER_NAME"})

# p90 ping latency by peer over 5m
histogram_quantile(
  0.90,
  sum by (le, peer) (
    rate(p2p_ping_latency_secs_bucket{cluster_name="$CLUSTER_NAME"}[5m])
  )
)

# Connection type breakdown (direct vs relayed)
max by (peer, type) (p2p_peer_connection_types{cluster_name="$CLUSTER_NAME"})
```

## PromQL — Duty performance

```promql
# Successful duties per type, last 5m
sum by (duty) (
  increase(core_tracker_success_duties_total{cluster_name="$CLUSTER_NAME"}[5m])
)

# Failed duties per type, last 5m (should be near zero)
sum by (duty, reason) (
  increase(core_tracker_failed_duties_total{cluster_name="$CLUSTER_NAME"}[5m])
)
```

## PromQL — Beacon node health

```promql
# BN call latency p95 by endpoint
histogram_quantile(
  0.95,
  sum by (le, endpoint) (
    rate(app_beacon_node_latency_secs_bucket{cluster_name="$CLUSTER_NAME"}[5m])
  )
)

# BN errors per endpoint
sum by (endpoint) (
  rate(app_beacon_node_errors_total{cluster_name="$CLUSTER_NAME"}[5m])
)

# Detected BN client per peer (useful for diversity audit)
max by (cluster_peer, beacon_id) (
  app_beacon_node_version{cluster_name="$CLUSTER_NAME"}
)
```

## PromQL — Health checks / alerts

```promql
# Currently failing health checks, with severity and description
max by (name, severity, description) (
  app_health_checks_failed_total{cluster_name="$CLUSTER_NAME"} > 0
)
```

## LogQL — Charon log search

```logql
# All charon errors in the window
{service_name="charon"} |= "error"

# Errors excluding noisy known-benign topics
{service_name="charon"} |= "error" != "context canceled"

# Filter by component (e.g. p2p, core, validatorapi)
{service_name="charon"} | json | component="p2p" | level="error"

# Logs around a specific slot
{service_name="charon"} |= "slot=12345678"

# Rate of errors per minute (for grafana stat panel)
sum(rate({service_name="charon"} |= "error" [1m]))
```

## LogQL — Beacon / execution / VC logs

```logql
# Lighthouse beacon node warnings
{container_name=~".*lighthouse.*"} |~ "(?i)warn|error"

# Lodestar VC missed duties
{container_name=~".*vc-lodestar.*"} |= "missed"

# Generic: any container, last 100 errors
{container_name=~".+"} |~ "(?i)error|panic" | line_format "{{.container_name}} {{.message}}"
```

## Tips

- All Charon metrics carry `cluster_peer` — add `by (cluster_peer)` to fan out per-operator.
- Loki labels in this stack come from Alloy's promtail-equivalent — common labels are `service_name`, `container_name`, `level`.
- For dashboard queries, prefer copying directly from `grafana/dashboards/*.json` (search for `"expr":` lines) so units and label selectors stay consistent.
