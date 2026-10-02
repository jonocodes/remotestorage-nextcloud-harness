#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
mkcol_abs "$(dav 'a/')"
mkcol_abs "$(dav 'a/b/')"

root="$(dav '')"
a="$(dav 'a/')"
ab="$(dav 'a/b/')"

put "$(dav 'a/b/c.txt')" 't3' >/dev/null

before_root="$(get_etag "$root" 0)"
before_a="$(get_etag "$a" 0)"
before_ab="$(get_etag "$ab" 0)"

http DELETE "$(dav 'a/b/c.txt')" >/dev/null

after_root="$(get_etag "$root" 0)"
after_a="$(get_etag "$a" 0)"
after_ab="$(get_etag "$ab" 0)"

changes="root=$(changed_str "$before_root" "$after_root") a/=$(changed_str "$before_a" "$after_a") a/b/=$(changed_str "$before_ab" "$after_ab")"
if [ "$(changed_str "$before_root" "$after_root")" = yes ] &&
   [ "$(changed_str "$before_a" "$after_a")" = yes ] &&
   [ "$(changed_str "$before_ab" "$after_ab")" = yes ]; then
  status=pass
  observed="all three ETags changed on delete (${changes})"
else
  status=fail
  observed="not all ETags changed on delete (${changes})"
fi

evidence="$(jq -nc \
  --arg br "$before_root" --arg ar "$after_root" \
  --arg ba "$before_a" --arg aa "$after_a" \
  --arg bab "$before_ab" --arg aab "$after_ab" \
  '{before:{root:$br,"a/":$ba,"a/b/":$bab},after:{root:$ar,"a/":$aa,"a/b/":$aab}}')"

emit_result T3 "$status" 'DELETE of $R/a/b/c.txt changes root, a/ and a/b/ ETags' "$observed" "$evidence"
