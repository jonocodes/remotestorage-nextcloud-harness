#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
root="$(dav '')"
before="$(get_etag "$root" 0)"

put "$(dav 't4.txt')" 't4' >/dev/null

start_ns="$(date +%s%N)"
first="$(get_etag "$root" 0)"
first_read_ms=$(( ( $(date +%s%N) - start_ns ) / 1000000 ))

if [ -n "$first" ] && [ -n "$before" ] && [ "$first" != "$before" ]; then
  status=pass
  observed="root ETag changed on the first read (${first_read_ms}ms after PUT returned)"
  latency_ms="$first_read_ms"
else
  latency_ms=''
  deadline_ms=$(( first_read_ms + 5000 ))
  while :; do
    current="$(get_etag "$root" 0)"
    now_ms=$(( ( $(date +%s%N) - start_ns ) / 1000000 ))
    if [ -n "$current" ] && [ "$current" != "$before" ]; then
      latency_ms="$now_ms"
      break
    fi
    if [ "$now_ms" -ge "$deadline_ms" ]; then
      break
    fi
  done
  if [ -n "$latency_ms" ]; then
    status=fail
    observed="root ETag changed only after ${latency_ms}ms, not on the first read"
  else
    status=fail
    observed="root ETag had still not changed 5s after PUT"
  fi
fi

evidence="$(jq -nc \
  --arg before "$before" --arg first "$first" \
  --arg latency "$latency_ms" --argjson first_read_ms "$first_read_ms" \
  '{before:$before,first_read_etag:$first,first_read_ms:$first_read_ms,change_latency_ms:($latency|if .=="" then null else tonumber end)}')"

emit_result T4 "$status" 'root ETag changes on the first PROPFIND after PUT returns' "$observed" "$evidence"
