#!/usr/bin/env bash
# B1: My Favorite Drinks (remotestorage/myfavoritedrinks) against the app.
# See ../../PLAN-explore.md. Serves the pinned static build on its own origin
# (`mfav`) and drives it in the pinned Playwright image: connect via the app's
# own widget/OAuth, add a drink, verify on the server, reload, delete.
#
# Evidence: explore/sessions/myfavoritedrinks/{result.json,run.log,artifacts/}
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh

REPO_URL="${REPO_URL:-https://github.com/remotestorage/myfavoritedrinks}"
PIN="${PIN:-b51503e62b2914bb88c1b9c86d07cf2e80b7d866}"
CO="explore/clients/myfavoritedrinks/checkout"
OUT="explore/sessions/myfavoritedrinks"
ART="$OUT/artifacts"
mkdir -p "$OUT" "$ART"
LOG="$OUT/run.log"
: > "$LOG"

DC="docker compose"
dce() { $DC exec -T "$@"; }
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
issue() { dce -u www-data nextcloud php occ remotestorage:token:issue "$1" "$2" explore 2>/dev/null | tr -d '\r\n'; }

# checkout (pinned) and serve
[ -d "$CO/.git" ] || git clone --quiet "$REPO_URL" "$CO"
git -C "$CO" fetch --quiet origin || true
git -C "$CO" checkout --quiet "$PIN"
log "=== B1 My Favorite Drinks @ ${PIN:0:7} ==="
$DC up -d mfav runner >/dev/null

TOKEN="$(issue "$NC_USER" '*:rw')"
# Start from a clean module (basic auth bypasses the app; folder DELETE works there).
dce curl-probe curl -sS -o /dev/null -u "${NC_USER}:${NC_PASS}" \
  -X DELETE "http://nextcloud/remote.php/dav/files/${NC_USER}/remoteStorage/myfavoritedrinks" || true

dce \
  -e EXPLORE=mfav -e APP_URL=http://mfav -e NC_URL=http://nextcloud \
  -e NC_USER="$NC_USER" -e NC_PASS="$NC_PASS" -e RS_TOKEN="$TOKEN" \
  -e EVIDENCE_DIR=/harness/"$ART" \
  -e PLAYWRIGHT_JSON_OUTPUT_NAME=/harness/"$OUT"/browser-raw.json \
  runner npx playwright test explore/explore-mfav.spec.ts --reporter=json,list 2>&1 | tee -a "$LOG" || true

jq '[.suites[].specs[] | {id: (.title | split(" ")[0]), check: .title,
     status: (.tests[0].status | if . == "expected" then "pass" elif . == "skipped" then "skipped" else "fail" end),
     observed: ([.tests[].results[] | (.stdout[]?.text), (.errors[]?.message // empty)] | join("") | rtrimstr("\n") | .[0:1500])}]' \
  "$OUT/browser-raw.json" > "$OUT/result.json" 2>/dev/null || echo '[]' > "$OUT/result.json"
rm -f "$OUT/browser-raw.json"

log "--- checks ---"
jq -r '.[] | "\(.status)\t\(.id)\t\(.observed[0:200])"' "$OUT/result.json" | tee -a "$LOG"
log "wrote $OUT/result.json; artifacts in $ART"
jq -e 'length > 0 and all(.status == "pass")' "$OUT/result.json" >/dev/null
