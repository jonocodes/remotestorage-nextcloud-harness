#!/usr/bin/env bash
# B3u: upstream RS Inspektor (raucao/inspektor, the original Ember 2.16 app) against
# the app. See ../../PLAN-explore.md and ../../sessions/inspektor-upstream/notes.md.
#
# Upstream constructs `new RemoteStorage({cache: false})` (app/services/storage.js)
# with remotestoragejs 1.1.0 and remotestorage-widget 1.3.0, so getListing returns
# full item metadata. Contrast B3 (explore/clients/inspektor), which tests m5x5's 2026
# Next.js rewrite with `cache: true`.
#
# Builds the pinned Ember app in node:8 (compose service inspektor-upstream-build),
# serves dist/ statically (service inspektor-upstream), reached by the browser as
# http://localhost:8082 via "loopback" (plain-http redirect URIs must be loopback).
# Seeds the same /b3/ tree as B3, plus pic-rsjs.png stored the way rs.js 1.x stores
# binaries ("image/png; charset=binary"), then drives it in the pinned Playwright image.
#
# Evidence: explore/sessions/inspektor-upstream/{result.json,run.log,artifacts/}
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh

REPO_URL="${REPO_URL:-https://gitea.kosmos.org/raucao/inspektor}"
PIN="${PIN:-0bece35c44f3e97f93d42b69c89a0f608f2b42d7}"
CO="explore/clients/inspektor-upstream/checkout"
OUT="explore/sessions/inspektor-upstream"
ART="$OUT/artifacts"
mkdir -p "$OUT" "$ART"
LOG="$OUT/run.log"
: > "$LOG"

DC="docker compose"
dce() { $DC exec -T "$@"; }
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
issue() { dce -u www-data nextcloud php occ remotestorage:token:issue "$1" "$2" explore 2>/dev/null | tr -d '\r\n'; }

# The inspektor-upstream service bind-mounts $CO/dist, so a `docker compose up` of the
# whole stack creates $CO (holding an empty dist/) before any clone; fetch into it in place.
if [ ! -d "$CO/.git" ]; then
  git init --quiet "$CO"
  git -C "$CO" remote add origin "$REPO_URL"
fi
git -C "$CO" fetch --quiet origin || true
git -C "$CO" checkout --quiet "$PIN"
log "=== B3u upstream RS Inspektor @ ${PIN:0:7} ==="

if [ ! -f "$CO/dist/index.html" ] || [ -n "${FORCE_BUILD:-}" ]; then
  log "building dist/ (npm ci && ember build --environment=production) in node:8"
  $DC run --rm inspektor-upstream-build >> "$LOG" 2>&1
fi
[ -f "$CO/dist/index.html" ] || { log "build did not produce $CO/dist"; exit 1; }
log "remotestoragejs $(jq -r .version "$CO/node_modules/remotestoragejs/package.json"), remotestorage-widget $(jq -r .version "$CO/node_modules/remotestorage-widget/package.json")"

# Recreate the static server: a rebuilt dist/ can be a new directory that an
# already-running container's bind mount no longer shows.
$DC up -d --force-recreate inspektor-upstream >/dev/null
$DC up -d runner loopback >/dev/null

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
  curl -sS -o /dev/null -H "$H" -X PUT -H "Content-Type: image/png; charset=binary" --data-binary @/tmp/pic.png "$S/pic-rsjs.png"
  curl -sS -o /dev/null -H "$H" -X PUT -H "Content-Type: text/plain" --data-binary "deep" "$S/sub/deep.txt"
'
log "seeded /b3/ (hello.json, notes.txt, pic.png, pic-rsjs.png, sub/deep.txt)"
log "--- server listing of /b3/ (Bearer *:rw) ---"
T="$RS_TOKEN" dce -e T curl-probe sh -c 'curl -sS -H "Authorization: Bearer $T" http://nextcloud/remote.php/dav/files/rstest/remoteStorage/b3/' \
  | jq . | tee -a "$LOG" > "$ART/server-listing-b3.json"

dce \
  -e EXPLORE=inspektor-upstream -e APP_URL=http://localhost:8082 -e NC_URL=http://nextcloud \
  -e NC_USER="$NC_USER" -e NC_PASS="$NC_PASS" -e RS_TOKEN \
  -e EVIDENCE_DIR=/harness/"$ART" \
  -e PLAYWRIGHT_JSON_OUTPUT_NAME=/harness/"$OUT"/browser-raw.json \
  runner npx playwright test explore/explore-inspektor-upstream.spec.ts --reporter=json,list 2>&1 | tee -a "$LOG" || true

jq '[.suites[].specs[] | {id: (.title | split(" ")[0]), check: .title,
     status: (.tests[0].status | if . == "expected" then "pass" elif . == "skipped" then "skipped" else "fail" end),
     observed: ([.tests[].results[] | (.stdout[]?.text), (.errors[]?.message // empty)] | join("") | rtrimstr("\n") | .[0:3000])}]' \
  "$OUT/browser-raw.json" > "$OUT/result.json" 2>/dev/null || echo '[]' > "$OUT/result.json"
rm -f "$OUT/browser-raw.json"

log "--- checks ---"
jq -r '.[] | "\(.status)\t\(.id)\n\(.observed)"' "$OUT/result.json" | tee -a "$LOG"
log "wrote $OUT/result.json; artifacts in $ART"
jq -e 'length > 0 and all(.status == "pass")' "$OUT/result.json" >/dev/null
