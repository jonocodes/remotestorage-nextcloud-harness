#!/usr/bin/env bash
# B2: Notes Together (DougReeder/notes-together) against the app.
# See ../../PLAN-explore.md. Builds the pinned React/Vite app, serves dist/ on its
# own origin (`nt`), then drives it in the pinned Playwright image: connect via the
# widget/OAuth (module `documents`), create a note, verify on the server, read it
# from a second browser context, delete it.
#
# Evidence: explore/sessions/notes-together/{result.json,run.log,artifacts/}
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh

REPO_URL="${REPO_URL:-https://github.com/DougReeder/notes-together}"
PIN="${PIN:-321c5a1b821d2e313642ddb4f945d58a687ee5c7}"
CO="explore/clients/notes-together/checkout"
OUT="explore/sessions/notes-together"
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
log "=== B2 Notes Together @ ${PIN:0:7} ==="

if [ ! -f "$CO/dist/index.html" ] || [ -n "${FORCE_BUILD:-}" ]; then
  log "building dist/ (npm ci && npm run build) in client-probe"
  dce client-probe sh -c "cd /harness/$CO && npm ci >/dev/null 2>&1 && npm run build" >> "$LOG" 2>&1
fi
[ -f "$CO/dist/index.html" ] || { log "build did not produce $CO/dist/index.html"; exit 1; }

$DC up -d nt runner >/dev/null

export RS_TOKEN="$(issue "$NC_USER" '*:rw')"
# Start from a clean module (basic auth bypasses the app; folder DELETE works there).
dce curl-probe curl -sS -o /dev/null -u "${NC_USER}:${NC_PASS}" \
  -X DELETE "http://nextcloud/remote.php/dav/files/${NC_USER}/remoteStorage/documents" || true

dce \
  -e EXPLORE=nt -e APP_URL=http://nt -e NC_URL=http://nextcloud \
  -e NC_USER="$NC_USER" -e NC_PASS="$NC_PASS" -e RS_TOKEN \
  -e EVIDENCE_DIR=/harness/"$ART" \
  -e PLAYWRIGHT_JSON_OUTPUT_NAME=/harness/"$OUT"/browser-raw.json \
  runner npx playwright test explore/explore-nt.spec.ts --reporter=json,list 2>&1 | tee -a "$LOG" || true

jq '[.suites[].specs[] | {id: (.title | split(" ")[0]), check: .title,
     status: (.tests[0].status | if . == "expected" then "pass" elif . == "skipped" then "skipped" else "fail" end),
     observed: ([.tests[].results[] | (.stdout[]?.text), (.errors[]?.message // empty)] | join("") | rtrimstr("\n") | .[0:1500])}]' \
  "$OUT/browser-raw.json" > "$OUT/result.json" 2>/dev/null || echo '[]' > "$OUT/result.json"
rm -f "$OUT/browser-raw.json"

log "--- checks ---"
jq -r '.[] | "\(.status)\t\(.id)\t\(.observed[0:200])"' "$OUT/result.json" | tee -a "$LOG"
log "wrote $OUT/result.json; artifacts in $ART"
jq -e 'length > 0 and all(.status == "pass")' "$OUT/result.json" >/dev/null
