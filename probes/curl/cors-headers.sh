#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

origin="${NC_CORS_ORIGIN:-http://localhost}"
foreign="${NC_FOREIGN_ORIGIN:-http://evil.example}"
out="${RESULTS_DIR}/${NC_VERSION}-${VARIANT}-cors-headers.txt"
file="${DAV_PREFIX}/cors-evidence.txt"

preflight() {
  curl -sS -o /dev/null -D - -X OPTIONS \
    -H "Origin: $1" \
    -H 'Access-Control-Request-Method: PROPFIND' \
    -H 'Access-Control-Request-Headers: authorization,depth' \
    "${NC_URL}${DAV_PREFIX}/" || true
}

curl -sS -o /dev/null -u "${NC_USER}:${NC_PASS}" -X PUT --data-binary 'cors evidence' \
  "${NC_URL}${file}" || true

{
  echo "# raw CORS headers"
  echo "# variant=${VARIANT} nextcloud=${NC_VERSION} origin=${origin} foreign=${foreign}"
  echo "# preflights carry no Authorization header, as a browser sends them"
  echo
  echo "## OPTIONS preflight for PROPFIND (allowed origin)"
  preflight "$origin"
  echo
  echo "## PROPFIND Depth: 1"
  curl -sS -o /dev/null -D - -X PROPFIND -u "${NC_USER}:${NC_PASS}" \
    -H "Origin: ${origin}" -H 'Depth: 1' \
    "${NC_URL}${DAV_PREFIX}/" || true
  echo
  echo "## GET"
  curl -sS -o /dev/null -D - -u "${NC_USER}:${NC_PASS}" \
    -H "Origin: ${origin}" "${NC_URL}${file}" || true
  echo
  echo "## PUT"
  curl -sS -o /dev/null -D - -u "${NC_USER}:${NC_PASS}" \
    -H "Origin: ${origin}" -X PUT --data-binary 'cors evidence 2' \
    "${NC_URL}${file}" || true
  echo
  echo "## DELETE"
  curl -sS -o /dev/null -D - -u "${NC_USER}:${NC_PASS}" \
    -H "Origin: ${origin}" -X DELETE "${NC_URL}${file}" || true
  echo
  echo "## OPTIONS preflight for PROPFIND (foreign origin, not allow-listed)"
  preflight "$foreign"
  echo
  echo "## PROPFIND Depth: 0 (foreign origin, not allow-listed)"
  curl -sS -o /dev/null -D - -X PROPFIND -u "${NC_USER}:${NC_PASS}" \
    -H "Origin: ${foreign}" -H 'Depth: 0' \
    "${NC_URL}${DAV_PREFIX}/" || true
  echo
  echo "## POST /index.php/login/v2 (allowed origin, unauthenticated)"
  curl -sS -o /dev/null -D - -X POST -H "Origin: ${origin}" \
    "${NC_URL}/index.php/login/v2" || true
  echo
} > "$out"

sed -i -E 's/^([Ss]et-[Cc]ookie: [^=]+=)[^;]*/\1<redacted>/' "$out"

echo "CORS headers written to ${out}"
