#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"

out="${1:?usage: run-all.sh <output.json>}"
raw="$(mktemp)"

for script in t*.sh; do
  if [ "$script" = "lib.sh" ]; then
    continue
  fi
  num="${script#t}"
  num="${num%.sh}"
  id="T$((10#${num}))"
  err="$(mktemp)"
  lines="$(bash "./${script}" 2>"${err}")" || true
  if [ -n "$lines" ]; then
    printf '%s\n' "$lines" >> "$raw"
  else
    bash -c 'source ./lib.sh; emit_error "$1" "$2"' _ "$id" \
      "$(tr '\n' ' ' < "${err}" | head -c 500)" >> "$raw"
  fi
  rm -f "$err"
done

jq -s '.' "$raw" > "$out"
rm -f "$raw"

echo "curl probes written to ${out}"
