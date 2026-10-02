#!/usr/bin/env bash
set -euo pipefail

: "${NC_URL:?NC_URL is required}"
: "${NC_USER:?NC_USER is required}"
: "${NC_PASS:?NC_PASS is required}"
: "${VARIANT:=unknown}"
: "${NC_VERSION:=unknown}"
: "${RESULTS_DIR:=/harness/results}"

DAV_PREFIX="/remote.php/dav/files/${NC_USER}/remotestorage"
FIXTURES_DIR="${RESULTS_DIR}/fixtures/${NC_VERSION}-${VARIANT}"
WORK_DIR="${TMPDIR:-/tmp}/rs-nc-probe"
mkdir -p "$FIXTURES_DIR" "$WORK_DIR"

dav() { printf '%s/%s' "$DAV_PREFIX" "$1"; }

emit_result() {
  local id="$1" status="$2" expected="$3" observed="$4" evidence="${5:-null}"
  jq -nc \
    --arg id "$id" \
    --arg variant "$VARIANT" \
    --arg nextcloud_version "$NC_VERSION" \
    --arg status "$status" \
    --arg expected "$expected" \
    --arg observed "$observed" \
    --argjson evidence "$evidence" \
    '{id:$id,variant:$variant,nextcloud_version:$nextcloud_version,status:$status,expected:$expected,observed:$observed,evidence:$evidence}'
}

emit_error() {
  local id="$1" message="$2"
  emit_result "$id" error "probe completes" "harness error: ${message}" \
    "$(jq -nc --arg m "$message" '{error:$m}')"
}

http() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "${WORK_DIR}/body.last" -D "${WORK_DIR}/headers.last" \
    -w '%{http_code}' -X "$method" -u "${NC_USER}:${NC_PASS}" "$@" "${NC_URL}${path}"
}

propfind() {
  local path="$1" depth="${2:-1}"
  http PROPFIND "$path" -H "Depth: ${depth}" -H 'Content-Type: application/xml'
}

prop_value() {
  local file="$1" href="$2" prop="$3"
  xmllint --xpath \
    "string(//*[local-name()='response'][*[local-name()='href' and normalize-space(text())='${href}']]/*[local-name()='propstat']/*[local-name()='prop']/*[local-name()='${prop}'])" \
    "$file" 2>/dev/null || true
}

prop_count() {
  local file="$1" href="$2" child="$3"
  xmllint --xpath \
    "count(//*[local-name()='response'][*[local-name()='href' and normalize-space(text())='${href}']]/*[local-name()='propstat']/*[local-name()='prop']/*[local-name()='resourcetype']/*[local-name()='${child}'])" \
    "$file" 2>/dev/null || echo 0
}

prop_etag() {
  local file="$1" href="$2"
  prop_value "$file" "$href" getetag
}

get_etag() {
  local path="$1" depth="${2:-0}"
  propfind "$path" "$depth" >/dev/null
  prop_etag "${WORK_DIR}/body.last" "$path"
}

last_header() {
  local name="$1"
  grep -i "^${name}:" "${WORK_DIR}/headers.last" | head -n1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true
}

normalize_etag() {
  printf '%s' "${1#W/}" | tr -d '"'
}

changed_str() {
  if [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ]; then
    echo yes
  else
    echo no
  fi
}

reset_root() {
  http DELETE "$DAV_PREFIX" -H 'Depth: infinity' >/dev/null || true
  local code
  code="$(http MKCOL "$DAV_PREFIX")"
  if [ "$code" != "201" ] && [ "$code" != "405" ]; then
    echo "reset_root failed: HTTP ${code}" >&2
    return 1
  fi
}

mkcol_abs() {
  local code
  code="$(http MKCOL "$1")"
  if [ "$code" != "201" ] && [ "$code" != "405" ]; then
    echo "MKCOL $1 failed: HTTP ${code}" >&2
    return 1
  fi
}

put() {
  local path="$1" body="$2"
  shift 2
  http PUT "$path" --data-binary "$body" "$@"
}
