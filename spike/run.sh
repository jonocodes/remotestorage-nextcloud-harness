#!/usr/bin/env bash
# Runs the PLAN-app.md spike: a fresh stack per Nextcloud version with the
# rsspike app, then spike/probe.sh (S1–S4, CORS, WebFinger) and the
# remoteStorage.js client checks (runner/spike.spec.ts).
set -euo pipefail
cd "$(dirname "$0")/.."

export NC_USER="${NC_USER:-rstest}" NC_PASS="${NC_PASS:-rstest-pass}"
export NC_ADMIN_USER="${NC_ADMIN_USER:-admin}" NC_ADMIN_PASSWORD="${NC_ADMIN_PASSWORD:-admin}"
export VARIANT=rsspike
read -r -a VERSIONS <<< "${VERSIONS:-35 34}"
mkdir -p results/spike

overall=0
for version in "${VERSIONS[@]}"; do
  export NC_VERSION="$version" NC_IMAGE="nextcloud:${version}-apache"
  echo "=== spike: Nextcloud ${version} ==="
  docker compose down -v --remove-orphans
  docker compose build curl-probe runner
  docker compose up -d
  ./scripts/wait-for-nextcloud.sh
  bash setup/common.sh
  bash setup/rsspike.sh

  docker compose exec -T curl-probe bash /harness/spike/probe.sh > "results/spike/${version}-checks.json" || overall=1
  docker compose exec -T -e VARIANT=rsspike \
    -e PLAYWRIGHT_JSON_OUTPUT_NAME="/harness/results/spike/${version}-client-raw.json" \
    runner npx playwright test spike.spec.ts --reporter=json,list >/dev/null || overall=1
  jq '[.suites[].specs[] | {id: (.title | split(" ")[0]), check: .title,
       status: (.tests[0].status | if . == "expected" then "pass" elif . == "skipped" then "skipped" else "fail" end),
       observed: ([.tests[].results[].stdout[]?.text] | join("") | rtrimstr("\n"))}]' \
    "results/spike/${version}-client-raw.json" > "results/spike/${version}-client.json"
  rm -f "results/spike/${version}-client-raw.json"
  docker compose logs nextcloud > "results/spike/${version}-nextcloud.log" 2>&1 || true

  echo "--- ${version} ---"
  jq -r '.[] | "\(.id)\t\(.status)\t\(.check)"' \
    "results/spike/${version}-checks.json" "results/spike/${version}-client.json"
  if jq -e '[.[] | select(.status != "pass")] | length > 0' \
      "results/spike/${version}-checks.json" "results/spike/${version}-client.json" >/dev/null; then
    overall=1
  fi
done
exit "$overall"
