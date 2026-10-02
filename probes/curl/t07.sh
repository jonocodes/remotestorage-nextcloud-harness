#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
file="$(dav 'f.txt')"
put "$file" 't7 original' >/dev/null

code="$(put "$file" 't7 stale write' -H 'If-Match: "stale"')"
http GET "$file" >/dev/null
body="$(cat "${WORK_DIR}/body.last")"

if [ "$code" = "412" ] && [ "$body" = 't7 original' ]; then
  status=pass
  observed="PUT with stale If-Match returned 412 and left the file unchanged"
else
  status=fail
  observed="PUT with stale If-Match returned ${code}, body now '${body}'"
fi

evidence="$(jq -nc --arg code "$code" --arg body "$body" --arg header 'If-Match: "stale"' \
  '{status:$code,body_after:$body,request_header:$header}')"

emit_result T7 "$status" 'PUT with If-Match: "stale" returns 412 and does not write' "$observed" "$evidence"
