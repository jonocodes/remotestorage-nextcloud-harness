#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
file="$(dav 'f.txt')"
put "$file" 't8 original' >/dev/null

code="$(put "$file" 't8 create-only write' -H 'If-None-Match: *')"
http GET "$file" >/dev/null
body="$(cat "${WORK_DIR}/body.last")"

if [ "$code" = "412" ] && [ "$body" = 't8 original' ]; then
  status=pass
  observed="PUT with If-None-Match: * on an existing file returned 412 and left it unchanged"
else
  status=fail
  observed="PUT with If-None-Match: * returned ${code}, body now '${body}'"
fi

evidence="$(jq -nc --arg code "$code" --arg body "$body" \
  '{status:$code,body_after:$body,request_header:"If-None-Match: *"}')"

emit_result T8 "$status" 'PUT with If-None-Match: * on an existing file returns 412' "$observed" "$evidence"
