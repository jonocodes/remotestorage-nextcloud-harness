#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
file="$(dav 'f.txt')"
put "$file" 't9 keep me' >/dev/null

code="$(http DELETE "$file" -H 'If-Match: "stale"')"
after_code="$(http GET "$file")"
body="$(cat "${WORK_DIR}/body.last")"

if [ "$code" = "412" ] && [ "$after_code" = "200" ] && [ "$body" = 't9 keep me' ]; then
  status=pass
  observed="DELETE with stale If-Match returned 412 and the file still exists"
else
  status=fail
  observed="DELETE with stale If-Match returned ${code}; subsequent GET returned ${after_code}"
fi

evidence="$(jq -nc --arg code "$code" --arg after "$after_code" --arg body "$body" \
  '{delete_status:$code,get_after_status:$after,body_after:$body,request_header:"If-Match: \"stale\""}')"

emit_result T9 "$status" 'DELETE with If-Match: "stale" returns 412 and does not delete' "$observed" "$evidence"
