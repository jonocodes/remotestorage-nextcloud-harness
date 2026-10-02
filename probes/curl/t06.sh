#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
root="$(dav '')"
file="$(dav 'f.txt')"

put "$file" 't6 hello' -H 'Content-Type: text/plain' >/dev/null

get_code="$(http GET "$file")"
get_etag_header="$(last_header ETag)"

propfind "$root" 1 >/dev/null
listing_etag="$(prop_etag "${WORK_DIR}/body.last" "$file")"

normalized_get="$(normalize_etag "$get_etag_header")"
normalized_listing="$(normalize_etag "$listing_etag")"

if [ -n "$normalized_get" ] && [ -n "$normalized_listing" ] && [ "$normalized_get" = "$normalized_listing" ]; then
  status=pass
  observed="GET ETag equals PROPFIND getetag after quote normalization"
else
  status=fail
  observed="GET ETag '${get_etag_header}' != PROPFIND getetag '${listing_etag}'"
fi

weak=no
case "$get_etag_header" in W/*) weak=yes ;; esac
case "$listing_etag" in W/*) weak=yes ;; esac

evidence="$(jq -nc \
  --arg get_status "$get_code" \
  --arg get_etag "$get_etag_header" \
  --arg listing_etag "$listing_etag" \
  --arg normalized_get "$normalized_get" \
  --arg normalized_listing "$normalized_listing" \
  --arg weak "$weak" \
  '{get_status:$get_status,get_etag:$get_etag,propfind_getetag:$listing_etag,normalized:{get:$normalized_get,propfind:$normalized_listing},weak:$weak}')"

emit_result T6 "$status" 'GET ETag equals parent PROPFIND getetag' "$observed" "$evidence"
