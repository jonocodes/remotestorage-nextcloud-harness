#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NC_USER="${NC_USER:-rstest}"
NC_PASS="${NC_PASS:-rstest-pass}"

occ() {
  docker compose exec -T -u www-data -e "OC_PASS=${NC_PASS}" nextcloud php occ "$@"
}

mkcol() {
  local path="$1"
  docker compose exec -T curl-probe curl -sS -o /dev/null -w '%{http_code}' \
    -u "${NC_USER}:${NC_PASS}" -X MKCOL "http://nextcloud${path}" || true
}
