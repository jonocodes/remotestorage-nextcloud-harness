#!/usr/bin/env bash
# PLAN-app.md spike checks S1–S4 plus CORS and WebFinger, against the rsspike
# variant. Runs in the curl-probe container; prints a JSON array.
set -uo pipefail
B="${NC_URL:-http://nextcloud}/remote.php/dav/files/${NC_USER:-rstest}/remotestorage"
TOKEN="Authorization: Bearer ${RS_TOKEN:-spike-token-notes-rw}"
BASIC=(-u "${NC_USER:-rstest}:${NC_PASS:-rstest-pass}")
results=()

req() { curl -s -o /tmp/body -D /tmp/hdr -w '%{http_code}' "$@"; }
hdr() { grep -i "^$1:" /tmp/hdr | head -n1 | tr -d '\r' | cut -d' ' -f2-; }
check() { # id, description, expected, observed
  local status=fail; [ "$3" = "$4" ] && status=pass
  results+=("$(jq -n --arg id "$1" --arg d "$2" --arg e "$3" --arg o "$4" --arg s "$status" \
    '{id:$id, check:$d, expected:$e, observed:$o, status:$s}')")
}
propfind_etag() { # path -> getetag of that node, quotes kept
  curl -s "${BASIC[@]}" -X PROPFIND -H 'Depth: 0' "$B/$1" \
    | xmllint --xpath 'string(//*[local-name()="getetag"])' - 2>/dev/null
}

for d in notes public other; do curl -s -o /dev/null "${BASIC[@]}" -X MKCOL "$B/$d"; done
curl -s -o /dev/null "${BASIC[@]}" -X PUT --data-binary secret "$B/other/x.txt"
curl -s -o /dev/null "${BASIC[@]}" -X PUT --data-binary pub "$B/public/p.txt"
curl -s -o /dev/null "${BASIC[@]}" -X DELETE "$B/notes/a.txt"

# S1: our bearer tokens reach our backend and log in for this request only.
check S1a "PUT document with token" 201 "$(req -H "$TOKEN" -X PUT -H 'Content-Type: text/plain' --data-binary hello "$B/notes/a.txt")"
check S1b "GET document with token" "200 hello" "$(req -H "$TOKEN" "$B/notes/a.txt") $(cat /tmp/body)"
check S1c "unknown token refused" 401 "$(req -H 'Authorization: Bearer wrong' "$B/notes/a.txt")"
check S1d "token outside its scope" 403 "$(req -H "$TOKEN" "$B/other/x.txt")"
check S1e "token outside the storage root" 403 "$(req -H "$TOKEN" "${B%/remotestorage}/")"
check S1f "non-remoteStorage method with token" 405 "$(req -H "$TOKEN" -X PROPFIND -H 'Depth: 1' "$B/notes/")"
check S1g "Basic auth unaffected" 200 "$(req "${BASIC[@]}" "$B/notes/a.txt")"
for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null -H "Authorization: Bearer wrong-$i" "$B/notes/a.txt"; done
good="$(curl -s -o /dev/null -w '%{http_code} %{time_total}' -H "$TOKEN" "$B/notes/a.txt")"
check S1h "good token not throttled after 10 bad ones (< 1 s)" "200 fast" \
  "$(awk '{print $1, ($2 < 1 ? "fast" : "slow " $2 "s")}' <<< "$good")"

# S2: folder GET with a token returns the remoteStorage listing.
code="$(req -H "$TOKEN" "$B/notes/")"
check S2a "folder GET with token" "200 application/ld+json" "$code $(hdr content-type)"
check S2b "listing has folder-description context and a.txt" "true" \
  "$(jq -r '(."@context" == "http://remotestorage.io/spec/folder-description") and (.items | has("a.txt"))' /tmp/body)"
listing_etag="$(jq -r '.items["a.txt"].ETag' /tmp/body)"
folder_etag="$(hdr etag)"
check S2c "folder GET with Basic auth unchanged (core HTML page)" "200 text/html" \
  "$(req "${BASIC[@]}" "$B/notes/") $(hdr content-type | cut -d';' -f1)"
check S2d "folder path without trailing slash is not a listing" 404 "$(req -H "$TOKEN" "$B/notes")"

# S3: ETags equal WebDAV's getetag.
req -H "$TOKEN" "$B/notes/a.txt" >/dev/null
doc_etag="$(hdr etag)"
check S3a "document GET ETag = PROPFIND getetag" "$(propfind_etag notes/a.txt)" "$doc_etag"
check S3b "listing item ETag = getetag without quotes" "$(propfind_etag notes/a.txt | tr -d '"')" "$listing_etag"
check S3c "folder GET ETag = PROPFIND getetag of the folder" "$(propfind_etag notes/)" "$folder_etag"

# S4: anonymous reads of public documents only.
check S4a "anonymous GET public document" "200 pub" "$(req "$B/public/p.txt") $(cat /tmp/body)"
check S4b "anonymous GET public folder listing" 401 "$(req "$B/public/")"
check S4c "anonymous GET public folder without slash" 404 "$(req "$B/public")"
check S4d "anonymous PUT into public" 401 "$(req -X PUT --data-binary x "$B/public/q.txt")"
check S4e "anonymous GET private document" 401 "$(req "$B/notes/a.txt")"

# CORS for any origin, bearer only.
check C1 "credential-less preflight from any origin" "204 *" \
  "$(req -X OPTIONS -H 'Origin: http://any.example' -H 'Access-Control-Request-Method: PUT' \
     -H 'Access-Control-Request-Headers: authorization,content-type,if-match' "$B/notes/a.txt") $(hdr access-control-allow-origin)"
req -H "$TOKEN" -H 'Origin: http://any.example' "$B/notes/a.txt" >/dev/null
check C2 "response exposes ETag" "* yes" \
  "$(hdr access-control-allow-origin) $(hdr access-control-expose-headers | grep -qi etag && echo yes || echo no)"
check C3 "error responses keep CORS" "403 *" \
  "$(req -H "$TOKEN" -H 'Origin: http://any.example' "$B/other/x.txt") $(hdr access-control-allow-origin)"
check C4 "no CORS outside the storage root" "none" \
  "$(req "${BASIC[@]}" -H 'Origin: http://any.example' "${B%/remotestorage}/" >/dev/null; hdr access-control-allow-origin || true)$( [ -z "$(hdr access-control-allow-origin)" ] && echo none)"

check C5 "Basic-auth request with an Origin gets no CORS (core behaviour kept)" "200 none" \
  "$(req "${BASIC[@]}" -H 'Origin: http://any.example' "$B/notes/a.txt") $( [ -z "$(hdr access-control-allow-origin)" ] && echo none || hdr access-control-allow-origin)"
check C6 "bad token 401 is readable cross-origin" "401 *" \
  "$(req -H 'Authorization: Bearer wrong' -H 'Origin: http://any.example' "$B/notes/a.txt") $(hdr access-control-allow-origin)"

# WebFinger.
code="$(req "${NC_URL:-http://nextcloud}/.well-known/webfinger?resource=acct:${NC_USER:-rstest}@nextcloud")"
check W1 "WebFinger answers with the remotestorage link, readable cross-origin" "200 * $B" \
  "$code $(hdr access-control-allow-origin) $(jq -r '.links[] | select(.rel=="http://tools.ietf.org/id/draft-dejong-remotestorage") | .href' /tmp/body)"
check W2 "WebFinger for an unknown user" 404 "$(req "${NC_URL:-http://nextcloud}/.well-known/webfinger?resource=acct:nobody@nextcloud")"

printf '%s\n' "${results[@]}" | jq -s .
