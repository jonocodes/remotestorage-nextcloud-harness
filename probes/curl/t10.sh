#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

reset_root
root="$(dav '')"
f1="$(dav 'f1.txt')"
f2="$(dav 'f2.txt')"
sub="$(dav 'sub/')"

put "$f1" 'one' -H 'Content-Type: text/plain' >/dev/null
put "$f2" '{"two": 2}' -H 'Content-Type: application/json' >/dev/null
mkcol_abs "$sub"

propfind "$root" 1 >/dev/null
cp "${WORK_DIR}/body.last" "${FIXTURES_DIR}/t10-propfind.xml"
xml="${WORK_DIR}/body.last"

etag_f1="$(prop_etag "$xml" "$f1")"
ct_f1="$(prop_value "$xml" "$f1" getcontenttype)"
len_f1="$(prop_value "$xml" "$f1" getcontentlength)"
lm_f1="$(prop_value "$xml" "$f1" getlastmodified)"

etag_f2="$(prop_etag "$xml" "$f2")"
ct_f2="$(prop_value "$xml" "$f2" getcontenttype)"
len_f2="$(prop_value "$xml" "$f2" getcontentlength)"
lm_f2="$(prop_value "$xml" "$f2" getlastmodified)"

etag_sub="$(prop_etag "$xml" "$sub")"
sub_is_collection="$(prop_count "$xml" "$sub" collection)"

response_count="$(xmllint --xpath "count(//*[local-name()='response'])" "$xml" 2>/dev/null || echo 0)"

missing=''
for required in "f1 getetag:$etag_f1" "f1 contenttype:$ct_f1" "f1 length:$len_f1" "f1 lastmodified:$lm_f1" \
                "f2 getetag:$etag_f2" "f2 contenttype:$ct_f2" "f2 length:$len_f2" "f2 lastmodified:$lm_f2" \
                "sub getetag:$etag_sub"; do
  if [ -z "${required#*:}" ]; then
    missing="${missing}${required%%:*}, "
  fi
done

if [ -z "$missing" ] && [ "$response_count" = "4" ] && [ "$sub_is_collection" = "1" ]; then
  status=pass
  observed="4 responses, files carry ETag/content-type/length/last-modified and sub/ has an ETag"
else
  status=fail
  observed="missing=[${missing%, }] responses=${response_count} sub_is_collection=${sub_is_collection}"
fi

mapping="$(jq -nc \
  --arg f1 "$f1" --arg e1 "$etag_f1" --arg c1 "$ct_f1" --arg l1 "$len_f1" --arg m1 "$lm_f1" \
  --arg f2 "$f2" --arg e2 "$etag_f2" --arg c2 "$ct_f2" --arg l2 "$len_f2" --arg m2 "$lm_f2" \
  --arg sub "$sub" --arg esub "$etag_sub" \
  '{
    files: [
      {href:$f1, etag:$e1, contenttype:$c1, contentlength:$l1, lastmodified:$m1},
      {href:$f2, etag:$e2, contenttype:$c2, contentlength:$l2, lastmodified:$m2}
    ],
    collections: [{href:$sub, etag:$esub}]
  }')"
printf '%s\n' "$mapping" > "${FIXTURES_DIR}/t10-mapping.json"

evidence="$(jq -nc --argjson mapping "$mapping" --argjson responses "$response_count" \
  --arg sub_is_collection "$sub_is_collection" \
  '{mapping:$mapping,response_count:$responses,sub_is_collection:($sub_is_collection|tonumber)}')"

emit_result T10 "$status" 'Depth: 1 PROPFIND exposes ETag, content type, length, last-modified and subfolder ETag' "$observed" "$evidence"
