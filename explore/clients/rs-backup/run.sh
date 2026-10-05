#!/usr/bin/env bash
# A2: rs-backup / rs-restore against the remoteStorage Nextcloud app.
# See ../../PLAN-explore.md. Expects the persistent stack up with the app
# installed (setup/common.sh, setup/rsapp.sh) and the client-probe service.
#
# Seeds a fixed tree in rstest's storage root, backs it up with rs-backup
# (WebFinger discovery, webfinger.js 2.x), restores into a fresh account with
# rs-restore, and verifies bytes, Content-Types and folder semantics.
#
# Evidence: explore/sessions/rs-backup/result.json and run.log
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh             # occ(), NC_USER, NC_PASS

SRC_USER="${NC_USER:-rstest}"
DST_USER="${DST_USER:-rsexplore-restore}"
DST_PASS="${DST_PASS:-rsexplore-pass}"
OUT="explore/sessions/rs-backup"
mkdir -p "$OUT"
LOG="$OUT/run.log"
: > "$LOG"

DC="docker compose"
dce() { $DC exec -T "$@"; }
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
basic() { # basic-auth WebDAV request against the source user
  dce curl-probe curl -sS -o /dev/null -w '%{http_code}' -u "${SRC_USER}:${NC_PASS}" "$@"
}
issue() { dce -u www-data nextcloud php occ remotestorage:token:issue "$1" "$2" explore 2>/dev/null | tr -d '\r\n'; }
bear() { # bear <user> <path> <token> -> response body
  dce -e U="$1" -e P="$2" -e T="$3" curl-probe \
    sh -c 'curl -sS -H "Authorization: Bearer $T" "http://nextcloud/remote.php/dav/files/$U/remoteStorage/$P"'
}
bear_hash() { # bear_hash <user> <path> <token> -> md5 of body
  dce -e U="$1" -e P="$2" -e T="$3" curl-probe \
    sh -c 'curl -sS -H "Authorization: Bearer $T" "http://nextcloud/remote.php/dav/files/$U/remoteStorage/$P" | md5sum | cut -d" " -f1'
}

S="http://nextcloud/remote.php/dav/files/${SRC_USER}/remoteStorage"
SRC_TOKEN="$(issue "$SRC_USER" '*:rw')"

log "=== A2 rs-backup (rs-backup $(dce client-probe rs-backup --version 2>/dev/null | tail -1), webfinger $(dce client-probe node -e "console.log(require('/opt/rs-backup/node_modules/webfinger.js/package.json').version)" 2>/dev/null)) ==="

# --- seed (idempotent) -------------------------------------------------------------
log "seeding ${SRC_USER} storage root"
basic -X DELETE "$S" >/dev/null || true
basic -X MKCOL "$S" >/dev/null
basic -X MKCOL "$S/notes" >/dev/null
basic -X MKCOL "$S/notes/sub" >/dev/null
basic -X MKCOL "$S/notes/empty" >/dev/null
basic -X PUT -H 'Content-Type: text/plain' --data-binary 'hello world' "$S/notes/hello.txt" >/dev/null
basic -X PUT -H 'Content-Type: application/json' --data-binary '{"a":1}' "$S/notes/sub/nested.json" >/dev/null
dce curl-probe sh -c 'head -c 64 /dev/urandom > /tmp/blob.bin; curl -sS -o /dev/null -u '"${SRC_USER}:${NC_PASS}"' -X PUT -H "Content-Type: application/octet-stream" --data-binary @/tmp/blob.bin '"$S"'/notes/blob.bin'
# A stored Content-Type that differs from Nextcloud's .json guess, via an app token.
dce curl-probe curl -sS -o /dev/null -H "Authorization: Bearer ${SRC_TOKEN}" \
  -X PUT -H 'Content-Type: text/plain' --data-binary '{"a":1}' "$S/notes/typed.json"

# --- backup ------------------------------------------------------------------------
log "rs-backup: ${SRC_USER}@nextcloud -> /tmp/rs-backup"
dce -e T="$SRC_TOKEN" client-probe sh -c 'rm -rf /tmp/rs-backup; rs-backup -o /tmp/rs-backup -u '"${SRC_USER}"'@nextcloud -t "$T"' 2>&1 | tee -a "$LOG"
backup_tree="$(dce client-probe sh -c 'cd /tmp/rs-backup 2>/dev/null && find . | sed "s|^\./||" | sort' | tr -d '\r')"

# --- restore into a fresh account --------------------------------------------------
dce -u www-data -e OC_PASS="$DST_PASS" nextcloud php occ user:add --password-from-env "$DST_USER" >/dev/null 2>&1 || true
DST_TOKEN="$(issue "$DST_USER" '*:rw')"
# A brand-new user's home storage is created lazily on first request. rs-restore's
# first requests race that creation and trip a core UNIQUE(oc_storages.id); warm the
# storage up serially first, and start from a clean target.
dce curl-probe curl -sS -o /dev/null -u "${DST_USER}:${DST_PASS}" \
  -X DELETE "http://nextcloud/remote.php/dav/files/${DST_USER}/remoteStorage" || true
bear "$DST_USER" '' "$DST_TOKEN" >/dev/null || true
log "rs-restore: /tmp/rs-backup -> ${DST_USER}@nextcloud"
dce -e T="$DST_TOKEN" client-probe sh -c 'rs-restore -i /tmp/rs-backup -u '"${DST_USER}"'@nextcloud -t "$T"' 2>&1 | tee -a "$LOG"

# --- verify ------------------------------------------------------------------------
FILES="notes/hello.txt notes/sub/nested.json notes/blob.bin notes/typed.json"
src_list="$(bear "$SRC_USER" 'notes/' "$SRC_TOKEN")"
dst_list="$(bear "$DST_USER" 'notes/' "$DST_TOKEN")"
checks="[]"
add_check() { checks="$(jq -c --arg id "$1" --arg st "$2" --arg o "$3" '. + [{id:$id,status:$st,observed:$o}]' <<<"$checks")"; }

for f in $FILES; do
  sh="$(bear_hash "$SRC_USER" "$f" "$SRC_TOKEN")"; dh="$(bear_hash "$DST_USER" "$f" "$DST_TOKEN")"
  [ "$sh" = "$dh" ] && add_check "A2-byte:$f" pass "$sh" || add_check "A2-byte:$f" fail "src=$sh dst=$dh"
done
for f in hello.txt typed.json blob.bin; do
  sc="$(jq -r --arg f "$f" '.items[$f]["Content-Type"] // "missing"' <<<"$src_list")"
  dc="$(jq -r --arg f "$f" '.items[$f]["Content-Type"] // "missing"' <<<"$dst_list")"
  [ "$sc" = "$dc" ] && [ "$sc" != missing ] && add_check "A2-ctype:$f" pass "$sc" || add_check "A2-ctype:$f" fail "src=$sc dst=$dc"
done
# Empty folders are not listed per spec, so rs-backup cannot see notes/empty.
grep -qx 'notes/empty' <<<"$backup_tree" && add_check A2-empty-folder fail "notes/empty present in backup" || add_check A2-empty-folder pass "notes/empty absent (listings omit empty folders)"
# rs-backup's 000_folder-description.json sidecars must not be restored as documents.
grep -q '000_folder-description' <<<"$(bear "$DST_USER" 'notes/' "$DST_TOKEN" | jq -r '.items|keys[]')" && add_check A2-sidecar fail "000_ restored as document" || add_check A2-sidecar pass "000_ not restored"

log "--- checks ---"
jq -r '.[] | "\(.status)\t\(.id)\t\(.observed)"' <<<"$checks" | tee -a "$LOG"
jq -n --arg user "$SRC_USER" --argjson checks "$checks" \
  '{client:"rs-backup", phase:"A2", user:$user, checks:$checks}' > "$OUT/result.json"
log "wrote $OUT/result.json"
jq -e '[.[] | select(.status=="fail")] | length == 0' <<<"$checks" >/dev/null || exit 1
