#!/usr/bin/env bash
# Discover the CDVN CL peer id and write optimum/config/app_conf.yml.
# Run from the CDVN root after the CL beacon node is up.
# Internal P2P ports match compose-cl.yml (container port on the dvnode network,
# not the host-mapped CL_PORT_P2P).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDVN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${CDVN_ROOT}/.env" ]] && set -a && source "${CDVN_ROOT}/.env" && set +a

CONFIG_DIR="${SCRIPT_DIR}/config"
SAMPLE="${CONFIG_DIR}/sample.app_conf.yml"
TARGET="${CONFIG_DIR}/app_conf.yml"

CL="${CL:-}"
CL_REST_URL="${CL_REST_URL:-http://127.0.0.1:${CL_PORT_HTTP:-5052}}"
GATEWAY_CLUSTER_ID="${GATEWAY_CLUSTER_ID:-}"

cl_p2p_port() {
  case "${1}" in
    cl-prysm) echo 13000 ;;
    cl-lighthouse|cl-lodestar|cl-teku|cl-nimbus|cl-grandine) echo 9000 ;;
    *)
      echo "Unsupported CL='${1}'. Set CL in .env to a compose-cl.yml service (e.g. cl-lighthouse)." >&2
      return 1
      ;;
  esac
}

if [[ ! -f "${SAMPLE}" ]]; then
  echo "Missing ${SAMPLE}" >&2
  exit 1
fi

if [[ -z "${CL}" ]]; then
  echo "CL is unset. Source a CDVN .env (e.g. CL=cl-lighthouse) and retry." >&2
  exit 1
fi

if [[ -z "${GATEWAY_CLUSTER_ID}" ]]; then
  echo "Set GATEWAY_CLUSTER_ID in .env to the Optimum cluster issued with your OPT_API_KEY." >&2
  echo "This is not the Charon cluster name. See optimum/README.md." >&2
  exit 1
fi

CL_P2P_INTERNAL_PORT="${CL_P2P_INTERNAL_PORT:-$(cl_p2p_port "${CL}")}"

echo "Fetching CL peer id from ${CL_REST_URL}/eth/v1/node/identity ..."
PEER_ID="$(curl -sf "${CL_REST_URL}/eth/v1/node/identity" | jq -er '.data.peer_id')"
if [[ -z "${PEER_ID}" || "${PEER_ID}" == "null" ]]; then
  echo "Failed to read CL peer id. Is the beacon node up and ${CL_REST_URL} reachable?" >&2
  exit 1
fi

mkdir -p "${SCRIPT_DIR}/identity/libp2p" "${SCRIPT_DIR}/identity/mump2p" "${SCRIPT_DIR}/cache"

sed \
  -e "s|REPLACE_GATEWAY_CLUSTER_ID|${GATEWAY_CLUSTER_ID}|g" \
  -e "s|REPLACE_CL_HOST|${CL}|g" \
  -e "s|REPLACE_CL_P2P_PORT|${CL_P2P_INTERNAL_PORT}|g" \
  -e "s|REPLACE_CL_PEER_ID|${PEER_ID}|g" \
  "${SAMPLE}" > "${TARGET}"

echo "Wrote ${TARGET}"
echo "  gateway_cluster_id: ${GATEWAY_CLUSTER_ID}"
echo "  direct_cl_peers: /dns4/${CL}/tcp/${CL_P2P_INTERNAL_PORT}/p2p/${PEER_ID}"
