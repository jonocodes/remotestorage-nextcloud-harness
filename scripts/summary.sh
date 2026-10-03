#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp)"
for f in results/*.json; do
  case "$f" in
    *-curl.json|*-browser.json|*-tokens.json) continue ;;
  esac
  jq -r '.[] | [.id, (.nextcloud_version + "/" + .variant), .status] | @tsv' "$f" >> "$tmp"
done

if [ ! -s "$tmp" ]; then
  echo "no merged results found under results/" >&2
  exit 1
fi

mapfile -t columns < <(cut -f2 "$tmp" | sort -u)
mapfile -t cases < <(cut -f1 "$tmp" | sort -u -V)

declare -A value
while IFS=$'\t' read -r id column status; do
  value["${id}|${column}"]="$status"
done < "$tmp"

printf '| Case |'
for column in "${columns[@]}"; do printf ' %s |' "$column"; done
printf '\n|---|'
for column in "${columns[@]}"; do printf '%s|' '---'; done
printf '\n'

for id in "${cases[@]}"; do
  printf '| %s |' "$id"
  for column in "${columns[@]}"; do
    printf ' %s |' "${value["${id}|${column}"]:--}"
  done
  printf '\n'
done

rm -f "$tmp"
