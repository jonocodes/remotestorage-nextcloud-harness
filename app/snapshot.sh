#!/usr/bin/env bash
# AT10 helper: a normalised snapshot of Basic-auth WebDAV responses under the
# storage root (what desktop/mobile clients send). Run once with the app
# disabled and once enabled; the two must be identical. Volatile headers
# (dates, cookies, request ids, CSP nonces) are dropped.
set -uo pipefail
S="${NC_URL:-http://nextcloud}/remote.php/dav/files/${NC_USER:-rstest}/remoteStorage"
BASIC=(-u "${NC_USER:-rstest}:${NC_PASS:-rstest-pass}")
VOLATILE='^(date|set-cookie|x-request-id|content-security-policy|expires|last-modified|x-debug-token|keep-alive|connection):'

snap() { # label, curl args...
  local label="$1"; shift
  local code
  code="$(curl -s -o /tmp/snap-body -D /tmp/snap-hdr -w '%{http_code}' "${BASIC[@]}" "$@")"
  local body; body="$(sha256sum < /tmp/snap-body | cut -c1-16)"
  # curl -I writes the headers into the -o file; a HEAD response has no body to compare.
  [[ " $* " == *" -I "* ]] && body="n/a (HEAD)"
  printf '## %s\nstatus %s\nbody %s\n' "$label" "$code" "$body"
  tr -d '\r' < /tmp/snap-hdr | grep -v '^HTTP/' | grep -v '^$' | tr 'A-Z' 'a-z' | grep -vE "$VOLATILE" | sort
}

snap "GET document" "$S/notes/fixture.txt"
snap "GET document with Origin" -H 'Origin: http://any.example' "$S/notes/fixture.txt"
snap "GET folder" "$S/notes/"
snap "PROPFIND root depth 1" -X PROPFIND -H 'Depth: 1' "$S/"
snap "PROPFIND folder depth 1 with Origin" -X PROPFIND -H 'Depth: 1' -H 'Origin: http://any.example' "$S/notes/"
snap "HEAD document" -I "$S/notes/fixture.txt"
snap "conditional GET" -H 'If-None-Match: "nope"' "$S/notes/fixture.txt"
snap "PUT into a missing folder" -X PUT --data-binary x "$S/missing/new.txt"
snap "MKCOL existing" -X MKCOL "$S/notes"
snap "GET outside the root" "${S%/remoteStorage}/remoteStorage-fixture-outside.txt"
