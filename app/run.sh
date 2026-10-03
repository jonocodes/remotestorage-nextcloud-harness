#!/usr/bin/env bash
# Runs PLAN-app.md's test cases against the real remoteStorage app, from a
# local checkout (RS_APP_DIR, default ../nextcloud-remotestorage). One fresh
# stack per Nextcloud version × variant:
#   rsapp                 the app alone
#   rsapp+webapppassword  the app next to WebAppPassword (coexistence)
# Results: results/app/<version>-<variant>-*.json
set -euo pipefail
cd "$(dirname "$0")/.."

export NC_USER="${NC_USER:-rstest}" NC_PASS="${NC_PASS:-rstest-pass}"
export NC_ADMIN_USER="${NC_ADMIN_USER:-admin}" NC_ADMIN_PASSWORD="${NC_ADMIN_PASSWORD:-admin}"
export NC_CORS_ORIGIN="${NC_CORS_ORIGIN:-http://origin}"
export RS_APP_DIR="$(cd "${RS_APP_DIR:-../nextcloud-remotestorage}" && pwd)"
read -r -a VERSIONS <<< "${VERSIONS:-35 34}"
read -r -a VARIANTS <<< "${VARIANTS:-rsapp rsapp+webapppassword}"
mkdir -p results/app
S="http://nextcloud/remote.php/dav/files/${NC_USER}/remoteStorage"

basic() { docker compose exec -T curl-probe curl -s -o /dev/null -w '%{http_code}' -u "${NC_USER}:${NC_PASS}" "$@"; }
occ() { docker compose exec -T -u www-data nextcloud php occ "$@"; }
issue() { occ remotestorage:token:issue "$NC_USER" "$1" "harness" | tr -d '\r\n'; }

overall=0
for version in "${VERSIONS[@]}"; do
  for variant in "${VARIANTS[@]}"; do
    export NC_VERSION="$version" NC_IMAGE="nextcloud:${version}-apache" VARIANT="$variant"
    out="results/app/${version}-${variant}"
    echo "=== app: Nextcloud ${version} / ${variant} ==="
    docker compose down -v --remove-orphans
    docker compose build curl-probe runner
    docker compose up -d
    ./scripts/wait-for-nextcloud.sh
    bash setup/common.sh
    wap_origin=""
    if [[ "$variant" == *webapppassword* ]]; then
      bash setup/webapppassword.sh
      wap_origin="$NC_CORS_ORIGIN"
    fi

    # AT10: Basic-auth WebDAV responses must not change when the app is enabled.
    basic -X MKCOL "$S" >/dev/null; basic -X MKCOL "$S/notes" >/dev/null
    basic -X PUT --data-binary fixture "$S/notes/fixture.txt" >/dev/null
    docker compose exec -T curl-probe bash /harness/app/snapshot.sh > "${out}-snapshot-before.txt"
    bash setup/rsapp.sh
    docker compose exec -T curl-probe bash /harness/app/snapshot.sh > "${out}-snapshot-after.txt"
    if diff -u "${out}-snapshot-before.txt" "${out}-snapshot-after.txt" > "${out}-snapshot.diff"; then
      at10='{"id":"AT10","check":"Basic-auth WebDAV responses identical with the app disabled and enabled","expected":"no diff","observed":"no diff","status":"pass"}'
    else
      at10="$(jq -n --arg o "$(head -c 2000 "${out}-snapshot.diff")" \
        '{id:"AT10", check:"Basic-auth WebDAV responses identical with the app disabled and enabled", expected:"no diff", observed:$o, status:"fail"}')"
    fi
    basic -X DELETE "$S" >/dev/null   # probes start from a user with no storage root

    docker compose exec -T \
      -e RS_TOKEN_RW="$(issue 'notes:rw')" -e RS_TOKEN_R="$(issue 'notes:r')" -e RS_TOKEN_ALL="$(issue '*:rw')" \
      -e WAP_ORIGIN="$wap_origin" \
      curl-probe bash /harness/app/probe.sh > "${out}-checks.json" || overall=1
    jq --argjson at10 "$at10" '. + [$at10]' "${out}-checks.json" > "${out}-checks.tmp" && mv "${out}-checks.tmp" "${out}-checks.json"

    docker compose exec -T -e VARIANT="$variant" -e NC_VERSION="$version" \
      -e PLAYWRIGHT_JSON_OUTPUT_NAME="/harness/results/app/${version}-${variant}-browser-raw.json" \
      runner npx playwright test app.spec.ts --reporter=json,list >/dev/null || overall=1
    jq '[.suites[].specs[] | {id: (.title | split(" ")[0]), check: .title,
         status: (.tests[0].status | if . == "expected" then "pass" elif . == "skipped" then "skipped" else "fail" end),
         observed: ([.tests[].results[] | (.stdout[]?.text), (.errors[]?.message // empty)] | join("") | rtrimstr("\n") | .[0:1500])}]' \
      "${out}-browser-raw.json" > "${out}-browser.json"
    rm -f "${out}-browser-raw.json"
    docker compose logs nextcloud > "${out}-nextcloud.log" 2>&1 || true
    docker compose exec -T nextcloud sh -c 'cat /var/www/html/data/nextcloud.log 2>/dev/null' \
      | jq -c 'select(.level >= 3) | {app, message: .message[0:300]}' > "${out}-errors.jsonl" 2>/dev/null || true

    echo "--- ${version} / ${variant} ---"
    jq -r '.[] | "\(.id)\t\(.status)\t\(.check)"' "${out}-checks.json" "${out}-browser.json"
    if jq -e '[.[] | select(.status != "pass")] | length > 0' "${out}-checks.json" "${out}-browser.json" >/dev/null; then
      overall=1
    fi
  done
done
exit "$overall"
