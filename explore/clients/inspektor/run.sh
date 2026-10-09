#!/usr/bin/env bash
# B3: RS Inspektor (m5x5/inspektor) against the app. See ../../PLAN-explore.md.
# Builds the pinned Next.js app, serves it with `next start` on its own origin
# (`inspektor`), seeds a small tree, then drives it in the pinned Playwright image:
# connect (scope *), browse, open a JSON document and an image, delete a document.
#
# Evidence: explore/sessions/inspektor/{result.json,run.log,artifacts/}
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh

REPO_URL="${REPO_URL:-https://github.com/m5x5/inspektor}"
PIN="${PIN:-b499d16cfef141b64cdb3429ccf9777730f84651}"
CO="explore/clients/inspektor/checkout"
OUT="explore/sessions/inspektor"
ART="$OUT/artifacts"
mkdir -p "$OUT" "$ART"
LOG="$OUT/run.log"
: > "$LOG"

DC="docker compose"
dce() { $DC exec -T "$@"; }
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
issue() { dce -u www-data nextcloud php occ remotestorage:token:issue "$1" "$2" explore 2>/dev/null | tr -d '\r\n'; }

[ -d "$CO/.git" ] || git clone --quiet "$REPO_URL" "$CO"
git -C "$CO" fetch --quiet origin || true
git -C "$CO" checkout --quiet "$PIN"
log "=== B3 RS Inspektor @ ${PIN:0:7} ==="

if [ ! -f "$CO/.next/BUILD_ID" ] || [ -n "${FORCE_BUILD:-}" ]; then
  log "building .next (npm ci && npm run build) in client-probe"
  dce client-probe sh -c "cd /harness/$CO && npm ci >/dev/null 2>&1 && npm run build" >> "$LOG" 2>&1
fi
[ -f "$CO/.next/BUILD_ID" ] || { log "build did not produce $CO/.next"; exit 1; }

$DC up -d inspektor runner loopback >/dev/null

export RS_TOKEN="$(issue "$NC_USER" '*:rw')"
S="http://nextcloud/remote.php/dav/files/${NC_USER}/remoteStorage"
# Seed a fixed tree (app token: PUT creates parents).
dce curl-probe curl -sS -o /dev/null -u "${NC_USER}:${NC_PASS}" -X DELETE "$S/b3" || true
T="$RS_TOKEN" dce -e T curl-probe sh -c '
  S=http://nextcloud/remote.php/dav/files/rstest/remoteStorage/b3
  H="Authorization: Bearer $T"
  curl -sS -o /dev/null -H "$H" -X PUT -H "Content-Type: application/json" --data-binary "{\"greeting\":\"hi\",\"nested\":{\"n\":42}}" "$S/hello.json"
  curl -sS -o /dev/null -H "$H" -X PUT -H "Content-Type: text/plain" --data-binary "plain text note" "$S/notes.txt"
  printf "%s" "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > /tmp/pic.png
  curl -sS -o /dev/null -H "$H" -X PUT -H "Content-Type: image/png" --data-binary @/tmp/pic.png "$S/pic.png"
  curl -sS -o /dev/null -H "$H" -X PUT -H "Content-Type: text/plain" --data-binary "deep" "$S/sub/deep.txt"
'
log "seeded /b3/ (hello.json, notes.txt, pic.png, sub/deep.txt)"

dce \
  -e EXPLORE=inspektor -e APP_URL=http://localhost:8084 -e NC_URL=http://nextcloud \
  -e NC_USER="$NC_USER" -e NC_PASS="$NC_PASS" -e RS_TOKEN \
  -e EVIDENCE_DIR=/harness/"$ART" \
  -e PLAYWRIGHT_JSON_OUTPUT_NAME=/harness/"$OUT"/browser-raw.json \
  runner npx playwright test explore/explore-inspektor.spec.ts --reporter=json,list 2>&1 | tee -a "$LOG" || true

jq '[.suites[].specs[] | {id: (.title | split(" ")[0]), check: .title,
     status: (.tests[0].status | if . == "expected" then "pass" elif . == "skipped" then "skipped" else "fail" end),
     observed: ([.tests[].results[] | (.stdout[]?.text), (.errors[]?.message // empty)] | join("") | rtrimstr("\n") | .[0:1500])}]' \
  "$OUT/browser-raw.json" > "$OUT/result.json" 2>/dev/null || echo '[]' > "$OUT/result.json"
rm -f "$OUT/browser-raw.json"

log "--- checks ---"
jq -r '.[] | "\(.status)\t\(.id)\t\(.observed[0:200])"' "$OUT/result.json" | tee -a "$LOG"
log "wrote $OUT/result.json; artifacts in $ART"
jq -e 'length > 0 and all(.status == "pass")' "$OUT/result.json" >/dev/null
