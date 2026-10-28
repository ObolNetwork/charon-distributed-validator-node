#!/usr/bin/env bash
# Checks this node's published ports and Grafana for internet exposure, and Grafana for signs of unauthorized changes.
# Releases before the Grafana hardening granted anonymous users the Admin role and published
# Grafana on all interfaces, so anyone who could reach port 3000 could change Grafana.
#
# Grafana used to keep its data in data/grafana. It now uses a fresh Docker volume, so this script
# inspects the old data/grafana for signs of tampering, after which data/grafana can be deleted.
#
# Usage, from the repository root, after upgrading: ./grafana/security-check.sh
# Reading data/grafana may need sudo, as it was written by Grafana's container.

set -uo pipefail

DB="${GRAFANA_DB:-data/grafana/grafana.db}"
PLUGINS_DIR="${GRAFANA_PLUGINS_DIR:-data/grafana/plugins}"
EXPECTED_DATASOURCES="Prometheus Loki Tempo"
# Plugins that Grafana 13 preinstalls and keeps updated in data/grafana/plugins by itself, including core
# datasources that Grafana now ships as separate plugins. See "Installing plugins" in Grafana's startup log.
EXPECTED_PLUGINS="elasticsearch grafana-advisor-app grafana-exploretraces-app grafana-lokiexplore-app
grafana-metricsdrilldown-app grafana-postgresql-datasource grafana-pyroscope-app grafana-pyroscope-datasource
influxdb jaeger loki mssql mysql opentsdb prometheus stackdriver tempo zipkin"
EXPECTED_PLUGINS="${EXPECTED_PLUGINS//$'\n'/ }"
findings=0
exposed=0

warn() {
  echo "  [!] $*"
  findings=$((findings + 1))
  return 0
}

# exposure reports a port reachable from the internet. It is counted apart from signs of tampering.
exposure() {
  echo "  [!] $*"
  exposed=$((exposed + 1))
  return 0
}

echo "== Grafana port binding"
if binding=$(docker compose port grafana 3000 2>/dev/null) && [[ -n "$binding" ]]; then
  echo "  grafana:3000 is published on $binding"
  case "$binding" in
    127.0.0.1:* | "[::1]:"*) echo "  OK: only reachable from this host" ;;
    *) exposure "Grafana is published on a non-loopback address. Docker-published ports bypass ufw, so it is reachable unless a provider or network firewall blocks it. Set MONITORING_IP_GRAFANA=127.0.0.1 in .env and run: docker compose up -d grafana" ;;
  esac
else
  echo "  grafana is not running or not published"
fi

echo
echo "== Other published ports"
# Container ports that peers must reach: EL, CL (incl. Prysm's 13000/12000) and charon.
P2P_PORTS=" 30303 9000 12000 13000 3610 "
before=$exposed
while read -r service ports; do
  IFS=',' read -ra mappings <<<"$ports"
  for mapping in "${mappings[@]}"; do
    mapping="${mapping# }"
    [[ "$mapping" == *"->"* ]] || continue
    host="${mapping%%->*}"
    container_port="${mapping##*->}"
    container_port="${container_port%%/*}"
    case "$host" in 127.0.0.1:* | "[::1]:"* | "::1:"*) continue ;; esac
    [[ "$P2P_PORTS" == *" $container_port "* || "$service" == grafana ]] && continue
    exposure "$service publishes port $container_port on $host. Docker-published ports bypass ufw, so it is reachable unless a provider or network firewall blocks it. Bind it to 127.0.0.1 in .env or docker-compose.override.yml."
  done
done < <(docker compose ps --format '{{.Service}} {{.Ports}}' 2>/dev/null)
[[ $exposed == "$before" ]] && echo "  OK: only P2P ports are published on non-loopback addresses"

echo
echo "== Grafana database ($DB)"
if [[ ! -e "$DB" ]]; then
  echo "  not found, nothing to check"
elif [[ ! -r "$DB" ]]; then
  echo "  cannot read it, re-run with sudo"
  exit 2
elif ! command -v python3 >/dev/null; then
  echo "  python3 is required to inspect the database"
  exit 2
else
  db_findings=$(
    python3 -I - "$DB" "$EXPECTED_DATASOURCES" <<'EOF'
import json
import sqlite3
import sys

db, expected = sys.argv[1], sys.argv[2].split()
conn = sqlite3.connect(f"file:{db}?mode=ro&immutable=1", uri=True)


def rows(query):
    try:
        return conn.execute(query).fetchall()
    except sqlite3.Error:
        return []


for login, created in rows("SELECT login, created FROM user WHERE is_service_account = 1"):
    print(f"service account: {login} (created {created})")
for name, created in rows("SELECT name, created FROM api_key"):
    print(f"API or service account token: {name} (created {created})")
for login, created in rows("SELECT login, created FROM user WHERE is_service_account = 0 AND login != 'admin'"):
    print(f"user: {login} (created {created})")
for name, kind, url, created in rows("SELECT name, type, url, created FROM data_source"):
    if name not in expected:
        print(f"datasource: {name} type={kind} url={url} (created {created})")
for name, created in rows("SELECT name, created FROM org WHERE id != 1"):
    print(f"organization: {name} (created {created})")
for title, created in rows("SELECT title, created FROM dashboard WHERE id NOT IN (SELECT dashboard_id FROM dashboard_provisioning)"):
    print(f"dashboard or folder not provisioned by this stack: {title} (created {created})")
for title, updated in rows("SELECT title, updated FROM alert_rule"):
    print(f"alert rule: {title} (updated {updated})")
for name, kind, created in rows("SELECT name, type, created FROM alert_notification"):
    print(f"notification channel: {name} type={kind} (created {created})")
contact_points = set()
for (config,) in rows("SELECT alertmanager_configuration FROM alert_configuration"):
    try:
        receivers = json.loads(config).get("alertmanager_config", {}).get("receivers") or []
    except (ValueError, AttributeError):
        continue
    for receiver in receivers:
        for integration in receiver.get("grafana_managed_receiver_configs") or []:
            # Grafana's default contact point emails a placeholder address.
            if "example@email.com" not in json.dumps(integration.get("settings")):
                contact_points.add((receiver.get("name"), integration.get("type")))
for name, kind in sorted(contact_points, key=str):
    print(f"contact point: {name} type={kind}")
# IDs keep counting up after rows are deleted, which reveals records that were created and later removed.
# Provisioning recreates a few datasources and dashboards on its own, so allow some of those.
ALLOWED_DELETIONS = {"user": 0, "api_key": 0, "org": 0, "alert_rule": 0, "data_source": 3, "dashboard": 10}
sequences = dict(rows("SELECT name, seq FROM sqlite_sequence"))
for table, allowed in ALLOWED_DELETIONS.items():
    count = rows(f"SELECT count(*) FROM {table}")
    if table in sequences and count and sequences[table] - count[0][0] > allowed:
        print(f"{sequences[table] - count[0][0]} {table} rows were created and later deleted")
EOF
  )
  if [[ -n "$db_findings" ]]; then
    while IFS= read -r line; do warn "$line"; done <<<"$db_findings"
  else
    echo "  OK: no service accounts, tokens, users, datasources, organizations, dashboards or alerting changes"
  fi
fi

echo
echo "== Grafana plugins ($PLUGINS_DIR)"
unexpected_plugins=0
if [[ -d "$PLUGINS_DIR" ]]; then
  for plugin in "$PLUGINS_DIR"/*; do
    [[ -e "$plugin" ]] || continue
    name=$(basename "$plugin")
    case " $EXPECTED_PLUGINS " in
      *" $name "*) echo "  preinstalled by Grafana: $name" ;;
      *)
        warn "installed plugin: $name"
        unexpected_plugins=1
        ;;
    esac
  done
fi
[[ "$unexpected_plugins" -eq 0 ]] && echo "  OK: no unexpected plugins installed"

echo
echo "== Repository files that Grafana mounted (grafana/)"
# Releases before the Grafana hardening mounted these writable, so Grafana could change its own provisioning.
if changed=$(git -c safe.directory="$PWD" status --porcelain --untracked-files=all -- grafana 2>/dev/null); then
  if [[ -n "$changed" ]]; then
    while IFS= read -r line; do warn "changed or added file: $line"; done <<<"$changed"
    echo "  Unless you made these changes, restore the files with: git checkout -- grafana && git clean -fd grafana"
    echo "  Also check 'git stash list', as 'git stash apply' during an upgrade would bring changes back."
  else
    echo "  OK: grafana/ matches this release"
  fi
else
  echo "  not a git checkout, cannot check"
fi

echo
if [[ "$exposed" -gt 0 ]]; then
  echo "Found $exposed exposed port(s). Fix the bindings listed above first."
fi
if [[ "$findings" -eq 0 ]]; then
  echo "No signs of unauthorized changes found."
else
  echo "Found $findings issue(s). This stack provisions everything Grafana needs from files, so anything listed"
  echo "above that you did not create yourself was most likely created by someone else. Please report it to"
  echo "security@obol.tech. Grafana encrypts stored secrets with a default key, so treat any credentials you"
  echo "stored in it, such as webhook URLs or tokens of contact points, as exposed and rotate them."
fi

if [[ -d "$(dirname "$DB")" ]]; then
  echo
  if [[ "$findings" -gt 0 ]]; then
    echo "Before deleting $(dirname "$DB"), keep a copy outside this repository for the investigation:"
    echo "  sudo tar czf ~/grafana-evidence-\$(date +%F).tar.gz $(dirname "$DB") && sha256sum ~/grafana-evidence-*.tar.gz"
  fi
  echo "Grafana no longer uses $(dirname "$DB"). Delete it with: sudo rm -rf $(dirname "$DB")"
fi

[[ "$findings" -eq 0 && "$exposed" -eq 0 ]]
