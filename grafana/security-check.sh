#!/usr/bin/env bash
# Checks this node's Grafana for internet exposure and for signs of unauthorized changes.
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
# Grafana Labs apps that Grafana preinstalls itself.
EXPECTED_PLUGINS="grafana-lokiexplore-app grafana-exploretraces-app grafana-metricsdrilldown-app grafana-pyroscope-app"
findings=0

warn() {
  echo "  [!] $*"
  findings=$((findings + 1))
}

echo "== Grafana port binding"
if binding=$(docker compose port grafana 3000 2>/dev/null) && [ -n "$binding" ]; then
  echo "  grafana:3000 is published on $binding"
  case "$binding" in
    127.0.0.1:* | "[::1]:"*) echo "  OK: only reachable from this host" ;;
    *) warn "Grafana is published on a non-loopback address. Docker-published ports bypass ufw, so it is reachable unless a provider or network firewall blocks it. Set MONITORING_IP_GRAFANA=127.0.0.1 in .env and run: docker compose up -d grafana" ;;
  esac
else
  echo "  grafana is not running or not published"
fi

echo
echo "== Grafana database ($DB)"
if [ ! -e "$DB" ]; then
  echo "  not found, nothing to check"
elif [ ! -r "$DB" ]; then
  echo "  cannot read it, re-run with sudo"
  exit 2
elif ! command -v python3 >/dev/null; then
  echo "  python3 is required to inspect the database"
  exit 2
else
  db_findings=$(
    python3 -I - "$DB" "$EXPECTED_DATASOURCES" <<'EOF'
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
EOF
  )
  if [ -n "$db_findings" ]; then
    while IFS= read -r line; do warn "$line"; done <<<"$db_findings"
  else
    echo "  OK: no service accounts, tokens, extra users or unexpected datasources"
  fi
fi

echo
echo "== Grafana plugins ($PLUGINS_DIR)"
unexpected_plugins=0
if [ -d "$PLUGINS_DIR" ]; then
  for plugin in "$PLUGINS_DIR"/*; do
    [ -e "$plugin" ] || continue
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
[ "$unexpected_plugins" -eq 0 ] && echo "  OK: no unexpected plugins installed"

echo
if [ "$findings" -eq 0 ]; then
  echo "No issues found."
else
  echo "Found $findings issue(s). This stack provisions everything Grafana needs from files, so service accounts,"
  echo "tokens, extra users, extra datasources or plugins were most likely created by someone else."
  echo "Please report it to security@obol.tech."
fi

if [ -d "$(dirname "$DB")" ]; then
  echo
  echo "Grafana no longer uses $(dirname "$DB"). Delete it with: sudo rm -rf $(dirname "$DB")"
fi

[ "$findings" -eq 0 ]
