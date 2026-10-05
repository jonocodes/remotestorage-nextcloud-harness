#!/usr/bin/env bash
# C1: 0dataapp/spec-check conformance suite against the app. See ../../PLAN-explore.md.
# A second remoteStorage REST-API conformance suite (alongside AT11's community
# api-test-suite). Runs its Node/mocha suite in client-probe, discovering the spec
# version from WebFinger and using three app tokens.
#
# Evidence: explore/sessions/spec-check/{result.json,run.log,artifacts/mocha.json}
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh

REPO_URL="${REPO_URL:-https://github.com/0dataapp/spec-check}"
PIN="${PIN:-e969675a41c8bbffa35dc8d8c0eea0e82846695b}"
CO="explore/clients/spec-check/checkout"
OUT="explore/sessions/spec-check"
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
log "=== C1 spec-check @ ${PIN:0:7} ==="
[ -d "$CO/node_modules" ] || dce client-probe sh -c "cd /harness/$CO && npm i --no-audit --no-fund" >> "$LOG" 2>&1

RW="$(issue "$NC_USER" 'api-test-suite:rw')"
RO="$(issue "$NC_USER" 'api-test-suite:r')"
GL="$(issue "$NC_USER" '*:rw')"

dce \
  -e DOTENV_CONFIG_QUIET=true \
  -e SERVER_URL=http://nextcloud -e ACCOUNT_HANDLE="$NC_USER" \
  -e TOKEN_READ_WRITE="$RW" -e TOKEN_READ_ONLY="$RO" -e TOKEN_GLOBAL="$GL" \
  client-probe sh -c "cd /harness/$CO && npx mocha --reporter json > /harness/$ART/mocha.json 2> /harness/$ART/mocha.err" 2>>"$LOG" || true

# dotenv can print a banner before the JSON; keep only from the first '{'.
awk 'f || /^\{/ { f = 1; print }' "$ART/mocha.json" > "$ART/mocha.clean.json"

# Known client/test assumptions that do not hold for this app's URL shape / Nextcloud:
#  - "other user rejects *": spec-check rewrites a baseURL ending in /<account>; ours
#    ends in /remoteStorage, so no rewrite happens and it re-tests the same account.
#    Cross-user rejection was verified separately (403, nothing written).
#  - "delete * removes file": it expects an ETag on the DELETE response; Nextcloud core
#    sends none, and remoteStorage.js never reads one (harness T12 amendment).
KNOWN='["other user rejects HEAD","other user rejects GET","other user rejects PUT","other user rejects DELETE","delete without folder removes file","delete with folder removes file"]'

stats="$(jq -r '"\(.stats.passes) passing, \(.stats.pending) pending, \(.stats.failures) failing"' "$ART/mocha.clean.json")"
fail_titles="$(jq -c '[.failures[].fullTitle]' "$ART/mocha.clean.json")"
unexpected="$(jq -c --argjson known "$KNOWN" '[.[] | select(. as $t | $known | index($t) | not)]' <<<"$fail_titles")"

log "spec-check: $stats"
log "known failures: $(jq -r 'join("; ")' <<<"$KNOWN")"
log "unexpected failures: $unexpected"

if [ "$(jq 'length' <<<"$unexpected")" -eq 0 ]; then
  checks="$(jq -cn --arg o "spec-check: $stats (all failures known/explained)" '{client:"spec-check",phase:"C1",checks:[{id:"C1",status:"pass",observed:$o}]}')"
else
  checks="$(jq -cn --arg o "spec-check: $stats; unexpected: $unexpected" '{client:"spec-check",phase:"C1",checks:[{id:"C1",status:"fail",observed:$o}]}')"
fi
printf '%s\n' "$checks" > "$OUT/result.json"
log "wrote $OUT/result.json (raw: $ART/mocha.json)"
jq -e '.checks | length > 0 and all(.status == "pass")' "$OUT/result.json" >/dev/null
