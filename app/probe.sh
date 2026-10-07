#!/usr/bin/env bash
# PLAN-app.md AT1, AT3, AT5–AT9 plus CORS, auth and throttling checks, against
# the real remoteStorage app. Runs in the curl-probe container; prints a JSON
# array. Tokens come from `occ remotestorage:token:issue` (see app/run.sh):
#   RS_TOKEN_RW  notes:rw    RS_TOKEN_R  notes:r    RS_TOKEN_ALL  *:rw
# Starts from a user with no storage root folder at all.
set -uo pipefail
NC="${NC_URL:-http://nextcloud}"
S="$NC/remote.php/dav/files/${NC_USER:-rstest}/remoteStorage"
RW="Authorization: Bearer ${RS_TOKEN_RW:?}"
RO="Authorization: Bearer ${RS_TOKEN_R:?}"
ALL="Authorization: Bearer ${RS_TOKEN_ALL:?}"
BASIC=(-u "${NC_USER:-rstest}:${NC_PASS:-rstest-pass}")
ORIGIN="Origin: http://any.example"
results=()

req() { curl -s -o /tmp/body -D /tmp/hdr -w '%{http_code}' "$@"; }
hdr() { grep -i "^$1:" /tmp/hdr | head -n1 | tr -d '\r' | cut -d' ' -f2-; }
has_hdr() { grep -qi "^$1:" /tmp/hdr && echo yes || echo no; }
check() { # id, description, expected, observed
  local status=fail; [ "$3" = "$4" ] && status=pass
  results+=("$(jq -n --arg id "$1" --arg d "$2" --arg e "$3" --arg o "$4" --arg s "$status" \
    '{id:$id, check:$d, expected:$e, observed:$o, status:$s}')")
}
propfind_etag() { # path below the root -> getetag, quotes kept
  curl -s "${BASIC[@]}" -X PROPFIND -H 'Depth: 0' "$S/$1" \
    | xmllint --xpath 'string(//*[local-name()="getetag"])' - 2>/dev/null
}
etag_of() { req "$@" >/dev/null; hdr etag; }
put() { curl -s -o /dev/null -w '%{http_code}' -H "$RW" -X PUT -H 'Content-Type: text/plain' --data-binary "$2" "$S/$1"; }

# --- AT1 WebFinger -----------------------------------------------------------
# Follow redirects like a browser (nginx's official config answers with a 301).
code="$(req -L -H "$ORIGIN" "$NC/.well-known/webfinger?resource=acct:${NC_USER:-rstest}@nextcloud")"
hops="$(grep -c '^HTTP/' /tmp/hdr)"
cors_hops="$(grep -ci '^access-control-allow-origin: \*' /tmp/hdr)"
link='.links[] | select(.rel=="http://tools.ietf.org/id/draft-dejong-remotestorage")'
check AT1a "WebFinger link href is the storage root" "200 $S" \
  "$code $(jq -r "$link | .href" /tmp/body)"
auth_url="$(jq -r "$link | .properties[\"http://tools.ietf.org/html/rfc6749#section-4.2\"]" /tmp/body)"
version="$(jq -r "$link | .properties[\"http://remotestorage.io/spec/version\"]" /tmp/body)"
# Nextcloud generates the pretty URL (no index.php) when rewrites are on; both work.
check AT1b "WebFinger advertises the OAuth dialog and spec version" "yes draft-dejong-remotestorage-22" \
  "$(grep -qE "^$NC(/index\.php)?/apps/remotestorage/oauth\$" <<< "$auth_url" && echo yes || echo "no ($auth_url)") $version"
check AT1c "WebFinger for an unknown user" 404 "$(req -L "$NC/.well-known/webfinger?resource=acct:nobody@nextcloud")"
check AT1d "WebFinger for another host" 404 "$(req -L "$NC/.well-known/webfinger?resource=acct:${NC_USER:-rstest}@other.example")"
check AT1e "every WebFinger response a browser sees carries CORS (redirects included)" "all" \
  "$( [ "$cors_hops" -ge "$hops" ] && echo all || echo "$cors_hops of $hops responses")"
# remoteStorage.js (webfinger.js 3) fetches with redirect: "manual"; in a browser that yields an
# opaque response, so any redirect breaks discovery whatever its headers.
check AT1f "WebFinger answered without a redirect" 1 "$hops"

# --- AT6 PUT creates parents, DELETE prunes them -----------------------------
check AT6a "PUT into a storage with no root folder creates every parent" 201 "$(put notes/a/b/c.txt deep)"
check AT6b "created parents are listed" "true" \
  "$(req -H "$RW" "$S/notes/a/" >/dev/null; jq -r '.items | has("b/")' /tmp/body)"
etag6c="$(etag_of -H "$RW" "$S/notes/a/b/c.txt")"
check AT6c "DELETE the only document (remoteStorage answers 200, not 204)" 200 "$(req -H "$RW" -X DELETE "$S/notes/a/b/c.txt")"
# remoteStorage spec >= 2: the DELETE response carries the deleted document's ETag.
check AT6c2 "DELETE response carries the deleted document's ETag" "$etag6c" "$(hdr etag)"
check AT6d "empty parents are left on disk (remoteStorage listings omit them)" 207 "$(req "${BASIC[@]}" -X PROPFIND -H 'Depth: 0' "$S/notes/")"
check AT6i "GET of a missing folder lists it as empty" "200 0" "$(req -H "$RW" "$S/notes/") $(jq -r '.items | length' /tmp/body)"
check AT6e "storage root itself is kept" 207 "$(req "${BASIC[@]}" -X PROPFIND -H 'Depth: 0' "$S/")"
put notes/doc.txt doc >/dev/null
check AT6f "PUT below a document" 409 "$(put notes/doc.txt/x.txt x)"
check AT6g "PUT to a folder path" 405 "$(req -H "$RW" -X PUT --data-binary x "$S/notes/")"
check AT6h "DELETE a folder path" 405 "$(req -H "$RW" -X DELETE "$S/notes/")"

# --- AT3 scopes --------------------------------------------------------------
check AT3a "notes:r reads notes" 200 "$(req -H "$RO" "$S/notes/doc.txt")"
check AT3b "notes:r cannot write" 403 "$(req -H "$RO" -X PUT --data-binary x "$S/notes/doc.txt")"
check AT3c "notes:rw cannot read another module" 403 "$(req -H "$RW" "$S/photos/a.jpg")"
check AT3d "notes:rw cannot list the root" 403 "$(req -H "$RW" "$S/")"
check AT3e "*:rw lists the root" 200 "$(req -H "$ALL" "$S/")"
check AT3f "notes:rw writes public/notes/" 201 "$(put public/notes/p.txt pub)"
check AT3g "notes:rw cannot write public/photos/" 403 "$(req -H "$RW" -X PUT --data-binary x "$S/public/photos/p.jpg")"
check AT3h "token cannot reach files outside the root" 403 "$(req -H "$ALL" "${S%/remoteStorage}/")"
check AT3i "WebDAV methods outside remoteStorage are refused" 405 "$(req -H "$ALL" -X PROPFIND -H 'Depth: 1' "$S/")"

# --- AT5 listings and ETags ----------------------------------------------------
put notes/sub/y.txt yy >/dev/null
code="$(req -H "$RW" "$S/notes/")"
check AT5a "folder GET returns a folder description" "200 application/ld+json" "$code $(hdr content-type)"
check AT5b "listing items and document metadata" "doc.txt sub/ text/plain 3" \
  "$(jq -r '[.items | keys[]] | join(" ")' /tmp/body) $(jq -r '.items["doc.txt"] | "\(."Content-Type") \(."Content-Length")"' /tmp/body)"
listing_doc="$(jq -r '.items["doc.txt"].ETag' /tmp/body)"
listing_sub="$(jq -r '.items["sub/"].ETag' /tmp/body)"
folder_etag="$(hdr etag)"
check AT5c "listing document ETag = getetag without quotes" "$(propfind_etag notes/doc.txt | tr -d '"')" "$listing_doc"
check AT5d "listing subfolder ETag = getetag without quotes" "$(propfind_etag notes/sub/ | tr -d '"')" "$listing_sub"
check AT5e "folder ETag header = folder getetag" "$(propfind_etag notes/)" "$folder_etag"
check AT5f "document ETag header = getetag" "$(propfind_etag notes/doc.txt)" "$(etag_of -H "$RW" "$S/notes/doc.txt")"
check AT5g "folder path without its slash is not a listing" 404 "$(req -H "$ALL" "$S/notes")"
check AT5i "a module token does not reach a slashless root path" 403 "$(req -H "$RW" "$S/notes")"
put_typed() { curl -s -o /dev/null -w '%{http_code}' -H "$RW" -X PUT -H "Content-Type: $2" --data-binary "$3" "$S/$1"; }
put_typed notes/typed.json 'application/json; charset=utf-8' '{"a":1}' >/dev/null
check AT5h "a document keeps the Content-Type it was PUT with (GET, HEAD, listing)" \
  "application/json; charset=utf-8|application/json; charset=utf-8|application/json; charset=utf-8" \
  "$(req -H "$RW" "$S/notes/typed.json" >/dev/null; hdr content-type)|$(req -I -H "$RW" "$S/notes/typed.json" >/dev/null; hdr content-type)|$(req -H "$RW" "$S/notes/" >/dev/null; jq -r '.items["typed.json"]["Content-Type"]' /tmp/body)"

# --- AT7 conditional requests --------------------------------------------------
current="$(etag_of -H "$RW" "$S/notes/doc.txt")"
check AT7a "stale If-Match PUT" 412 "$(req -H "$RW" -X PUT -H 'If-Match: "stale"' --data-binary changed "$S/notes/doc.txt")"
check AT7b "stale If-Match DELETE" 412 "$(req -H "$RW" -X DELETE -H 'If-Match: "stale"' "$S/notes/doc.txt")"
check AT7c "If-None-Match: * on an existing document" 412 "$(req -H "$RW" -X PUT -H 'If-None-Match: *' --data-binary x "$S/notes/doc.txt")"
check AT7d "document unchanged after failed preconditions" doc "$(curl -s -H "$RW" "$S/notes/doc.txt")"
check AT7e "If-None-Match current ETag on a document" 304 "$(req -H "$RW" -H "If-None-Match: $current" "$S/notes/doc.txt")"
folder_now="$(etag_of -H "$RW" "$S/notes/")"
check AT7f "If-None-Match current ETag on a folder" 304 "$(req -H "$RW" -H "If-None-Match: $folder_now" "$S/notes/")"
check AT7g "If-Match current ETag PUT succeeds (200, not 204)" 200 "$(req -H "$RW" -X PUT -H "If-Match: $current" --data-binary doc2 "$S/notes/doc.txt")"
check AT7h "If-Match PUT to a missing document creates no folders" "412 404" \
  "$(req -H "$RW" -X PUT -H 'If-Match: "x"' --data-binary x "$S/notes/ghost/g.txt") $(req "${BASIC[@]}" -X PROPFIND -H 'Depth: 0' "$S/notes/ghost/")"
# Browsers always ask for compression; the ETag of a compressed read must work for the next write.
long="$(printf 'line of text for compression %.0s' $(seq 1 40))"
put_typed notes/gz.txt text/plain "$long" >/dev/null
req -H "$RW" -H 'Accept-Encoding: gzip, deflate, br' "$S/notes/gz.txt" >/dev/null
gz_etag="$(hdr etag)"; gz_enc="$(hdr content-encoding)"
check AT7i "write with If-Match from a compressed read succeeds" 200 \
  "$(req -H "$RW" -X PUT -H "If-Match: $gz_etag" -H 'Content-Type: text/plain' --data-binary changed "$S/notes/gz.txt")"
check AT7j "compression as served (informational: identity on Apache with mod_php)" "${gz_enc:-identity}" "${gz_enc:-identity}"
# Nextcloud derives file ETags from mtime in whole seconds + inode + size: a same-size
# overwrite within one second must still get a new ETag, or If-Match cannot detect it.
put_typed notes/fast.txt text/plain aaaa >/dev/null
fast1="$(etag_of -H "$RW" "$S/notes/fast.txt")"
curl -s -o /dev/null -H "$RW" -X PUT -H 'Content-Type: text/plain' --data-binary bbbb -D /tmp/fast-hdr "$S/notes/fast.txt"
fast2="$(grep -i '^etag:' /tmp/fast-hdr | tr -d '\r' | cut -d' ' -f2)"
check AT7k "same-size overwrite within a second gets a new ETag; the old one is then stale" "changed 412 bbbb" \
  "$( [ -n "$fast2" ] && [ "$fast1" != "$fast2" ] && echo changed || echo "same ($fast1)") $(req -H "$RW" -X PUT -H "If-Match: $fast1" --data-binary cccc "$S/notes/fast.txt") $(curl -s -H "$RW" "$S/notes/fast.txt")"

# --- AT8 folder ETags propagate to the root ------------------------------------
before="$(etag_of -H "$ALL" "$S/") $(etag_of -H "$RW" "$S/notes/") $(etag_of -H "$RW" "$S/notes/sub/")"
put notes/sub/z.txt z >/dev/null
after="$(etag_of -H "$ALL" "$S/") $(etag_of -H "$RW" "$S/notes/") $(etag_of -H "$RW" "$S/notes/sub/")"
changed=0; for i in 1 2 3; do [ "$(cut -d' ' -f$i <<< "$before")" != "$(cut -d' ' -f$i <<< "$after")" ] && changed=$((changed + 1)); done
check AT8a "create: root, module and parent folder ETags all change" 3 "$changed"
before="$after"
req -H "$RW" -X DELETE "$S/notes/sub/z.txt" >/dev/null
after="$(etag_of -H "$ALL" "$S/") $(etag_of -H "$RW" "$S/notes/") $(etag_of -H "$RW" "$S/notes/sub/")"
changed=0; for i in 1 2 3; do [ "$(cut -d' ' -f$i <<< "$before")" != "$(cut -d' ' -f$i <<< "$after")" ] && changed=$((changed + 1)); done
check AT8b "delete: root, module and parent folder ETags all change" 3 "$changed"

# --- AT9 public documents --------------------------------------------------------
check AT9a "anonymous GET of a public document" "200 pub" "$(req "$S/public/notes/p.txt") $(cat /tmp/body)"
check AT9b "anonymous GET of a public listing" 401 "$(req "$S/public/notes/")"
check AT9c "anonymous GET of a public folder without its slash" 404 "$(req "$S/public/notes")"
check AT9d "anonymous PUT into public" 401 "$(req -X PUT --data-binary x "$S/public/notes/q.txt")"
check AT9e "anonymous GET of a private document" 401 "$(req "$S/notes/doc.txt")"

# --- CORS ------------------------------------------------------------------------
check C1 "credential-less preflight from any origin echoes it" "204 http://any.example" \
  "$(req -X OPTIONS -H "$ORIGIN" -H 'Access-Control-Request-Method: PUT' \
     -H 'Access-Control-Request-Headers: authorization,content-type,if-match' "$S/notes/doc.txt") $(hdr access-control-allow-origin)"
req -H "$RW" -H "$ORIGIN" "$S/notes/doc.txt" >/dev/null
check C2 "token response: origin echoed, ETag exposed, no credentials" "http://any.example yes no" \
  "$(hdr access-control-allow-origin) $(hdr access-control-expose-headers | grep -qi etag && echo yes || echo no) $(has_hdr access-control-allow-credentials)"
check C3 "error responses keep CORS" "403 http://any.example" "$(req -H "$RW" -H "$ORIGIN" "$S/photos/x") $(hdr access-control-allow-origin)"
check C4 "bad token 401 is readable cross-origin" "401 http://any.example" \
  "$(req -H "Authorization: Bearer rs_$(printf 'x%.0s' {1..43})" -H "$ORIGIN" "$S/notes/doc.txt") $(hdr access-control-allow-origin)"
check C5 "Basic-auth request with an Origin gets no CORS" "200 no" \
  "$(req "${BASIC[@]}" -H "$ORIGIN" "$S/notes/doc.txt") $(has_hdr access-control-allow-origin)"
check C6 "no CORS outside the storage root" "no" \
  "$(req "${BASIC[@]}" -H "$ORIGIN" -X PROPFIND -H 'Depth: 0' "${S%/remoteStorage}/" >/dev/null; has_hdr access-control-allow-origin)"

# --- Auth: request-only logins, foreign bearer tokens, throttling ---------------
req -H "$RW" -c /tmp/jar "$S/notes/doc.txt" >/dev/null
check A1 "cookies from a token request do not log anyone in" 401 \
  "$(req -b /tmp/jar -X PROPFIND -H 'Depth: 0' "${S%/remoteStorage}/")"
slow=0
for i in 1 2 3 4 5 6; do
  t="$(curl -s -o /dev/null -w '%{time_total}' -H "Authorization: Bearer core-style-$i" "$S/notes/doc.txt")"
  awk -v t="$t" 'BEGIN { exit !(t > 1) }' && slow=$((slow + 1))
done
check A2 "non-rs_ bearer tokens pass through to core, unthrottled by the app" 0 "$slow"
for i in 1 2 3 4 5 6; do
  curl -s -o /dev/null -H "Authorization: Bearer rs_$(printf "%043d" "$i")" "$S/notes/doc.txt"
done
t="$(curl -s -o /dev/null -w '%{time_total}' -H "Authorization: Bearer rs_$(printf "%043d" 7)" "$S/notes/doc.txt")"
check A3 "repeated bad rs_ tokens are throttled (7th attempt > 1 s)" slowed \
  "$(awk -v t="$t" 'BEGIN { print (t > 1 ? "slowed" : "not slowed (" t "s)") }')"

# --- Coexistence with WebAppPassword (only when it is installed) ----------------
if [ -n "${WAP_ORIGIN:-}" ]; then
  req -H "$RW" -H "Origin: $WAP_ORIGIN" "$S/notes/doc.txt" >/dev/null
  check W1 "token request from a WebAppPassword origin: exactly one Allow-Origin, ETag exposed" "1 yes" \
    "$(grep -ci '^access-control-allow-origin:' /tmp/hdr) $(hdr access-control-expose-headers | grep -qi etag && echo yes || echo no)"
  req -X OPTIONS -H "Origin: $WAP_ORIGIN" -H 'Access-Control-Request-Method: PUT' \
    -H 'Access-Control-Request-Headers: authorization' "$S/notes/doc.txt" >/dev/null
  check W2 "preflight from a WebAppPassword origin: exactly one Allow-Origin" 1 "$(grep -ci '^access-control-allow-origin:' /tmp/hdr)"
fi

printf '%s\n' "${results[@]}" | jq -s .
