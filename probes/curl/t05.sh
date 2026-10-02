#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
mkcol_abs "$(dav 'x/')"
mkcol_abs "$(dav 'y/')"

root="$(dav '')"
y="$(dav 'y/')"

before_y="$(get_etag "$y" 0)"
before_root="$(get_etag "$root" 0)"

put "$(dav 'x/f.txt')" 't5' >/dev/null

after_y="$(get_etag "$y" 0)"
after_root="$(get_etag "$root" 0)"

if [ -n "$before_y" ] && [ "$before_y" = "$after_y" ]; then
  status=pass
  observed="sibling y/ ETag unchanged; root changed=$(changed_str "$before_root" "$after_root")"
else
  status=fail
  observed="sibling y/ ETag changed: ${before_y} -> ${after_y}"
fi

evidence="$(jq -nc \
  --arg by "$before_y" --arg ay "$after_y" \
  --arg br "$before_root" --arg ar "$after_root" \
  '{y_before:$by,y_after:$ay,root_before:$br,root_after:$ar}')"

emit_result T5 "$status" 'PUT under x/ leaves sibling y/ ETag unchanged' "$observed" "$evidence"
