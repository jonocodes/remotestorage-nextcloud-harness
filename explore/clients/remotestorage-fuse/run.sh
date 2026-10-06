#!/usr/bin/env bash
# A1: remotestorage-fuse (remotestorage/fuse) against the remoteStorage Nextcloud app.
# See ../../PLAN-explore.md. Mounts the storage root with a *:rw token (base_url +
# token, no WebFinger/OAuth) and exercises it as a filesystem.
#
# Known outcome (2026-10-05): the client is stale. Its listing parser handles the
# pre-folder-description ("draft-dejong-remotestorage-02") flat {name: rev} format and
# mangles the current JSON, so the tree does not resolve. This script captures that
# evidence; it does not patch the client.
#
# Evidence: explore/sessions/remotestorage-fuse/{result.json,run.log,artifacts/}
set -euo pipefail

cd "$(dirname "$0")/../../.."   # harness root
source setup/lib.sh             # occ(), NC_USER, NC_PASS

REPO_URL="${REPO_URL:-https://github.com/remotestorage/fuse}"
PIN="${PIN:-2a25a1c407fe7dda6b5d8683afd3390b7cf9e57c}"
CO="explore/clients/remotestorage-fuse/checkout"
OUT="explore/sessions/remotestorage-fuse"
ART="$OUT/artifacts"
mkdir -p "$OUT" "$ART"
LOG="$OUT/run.log"
: > "$LOG"

DC="docker compose"
dce() { $DC exec -T "$@"; }
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
issue() { dce -u www-data nextcloud php occ remotestorage:token:issue "$1" "$2" explore 2>/dev/null | tr -d '\r\n'; }
basic() { dce curl-probe curl -sS -o /dev/null -w '%{http_code}' -u "${NC_USER}:${NC_PASS}" "$@"; }

S="http://nextcloud/remote.php/dav/files/${NC_USER}/remoteStorage"
TOKEN="$(issue "$NC_USER" '*:rw')"

checks="[]"
add_check() { checks="$(jq -c --arg id "$1" --arg st "$2" --arg o "$3" '. + [{id:$id,status:$st,observed:$o}]' <<<"$checks")"; }

# --- checkout + build --------------------------------------------------------------
mkdir -p "$(dirname "$CO")"
[ -d "$CO/.git" ] || git clone --quiet "$REPO_URL" "$CO"
git -C "$CO" fetch --quiet origin || true
git -C "$CO" checkout --quiet "$PIN"
log "=== A1 remotestorage-fuse @ ${PIN:0:7} ==="
# GCC >= 10 defaults to -fno-common; this 2013 code needs -fcommon.
dce client-probe sh -c '
  cd /harness/'"$CO"' || exit 1
  make clean >/dev/null 2>&1
  make CFLAGS="-ggdb -std=gnu99 $(getconf LFS_CFLAGS) $(pkg-config --cflags fuse) $(pkg-config --cflags libcurl) -fcommon" >/dev/null 2>&1
  ls rs-mount' >/dev/null \
  && add_check A1-build pass "built $CO/rs-mount" || add_check A1-build fail "build failed"

# --- seed a known tree -------------------------------------------------------------
basic -X DELETE "$S" >/dev/null || true
basic -X MKCOL "$S" >/dev/null
basic -X MKCOL "$S/notes" >/dev/null
basic -X MKCOL "$S/notes/sub" >/dev/null
basic -X PUT -H 'Content-Type: text/plain' --data-binary 'hello world' "$S/notes/hello.txt" >/dev/null

# --- mount -------------------------------------------------------------------------
# The app answers rel=http://tools.ietf.org/id/draft-dejong-remotestorage (rs.js accepts it too).
BASE_URL="$(dce curl-probe curl -sS "http://nextcloud/.well-known/webfinger?resource=acct:${NC_USER}@nextcloud" | jq -r '.links[]|select(.rel|test("remotestorage"))|.href' | head -1)"
log "base_url=$BASE_URL"
cleanup() { dce client-probe sh -c 'umount /mnt/rs 2>/dev/null || fusermount -u /mnt/rs 2>/dev/null || true'; }
trap cleanup EXIT

T="$TOKEN" dce -e B="$BASE_URL" -e T client-probe sh -c '
  cd /harness/'"$ART"'
  M=/mnt/rs; mkdir -p "$M"; umount "$M" 2>/dev/null || true
  /harness/'"$CO"'/rs-mount -o base_url="$B",token="$T" "$M" 2>/tmp/mount.err
  sleep 1
' || true
if dce client-probe sh -c 'mount | grep -q " /mnt/rs "'; then
  add_check A1-mount pass "mounted on /mnt/rs"
else
  add_check A1-mount fail "not mounted: $(dce client-probe cat /tmp/mount.err 2>/dev/null)"
fi

# Capture the raw client behaviour (tolerate failures), plus the server's own listing.
T="$TOKEN" dce -e T client-probe sh -c '
  { echo "--- ls -1 /mnt/rs ---"; ls -1 /mnt/rs 2>&1; } > /harness/'"$ART"'/ls-root.txt
  { echo "--- ls /mnt/rs/notes ---"; ls -la /mnt/rs/notes 2>&1; } > /harness/'"$ART"'/ls-notes.txt
  { echo "--- cat /mnt/rs/notes/hello.txt ---"; cat /mnt/rs/notes/hello.txt 2>&1; } > /harness/'"$ART"'/cat-hello.txt
  { echo "--- write /mnt/rs/notes/fusefile.txt ---"; printf "written by fuse" > /mnt/rs/notes/fusefile.txt 2>&1; echo "rc=$?"; } > /harness/'"$ART"'/write.txt
  cp /tmp/mount.err /harness/'"$ART"'/mount.err 2>/dev/null || true
' || true
dce curl-probe curl -sS -H "Authorization: Bearer ${TOKEN}" "$S/notes/" > "$ART/app-listing.json" || true

clean() { sed -e 's/\x1b\[[0-9;]*m//g' -e '/Executing external compose provider/d' -e '/^<<<<$/d' -e '/^$/d'; }
set +e
root_ls="$( { dce client-probe ls -1 /mnt/rs 2>&1 || true; } | clean | tr '\n' ' ' | sed 's/  */ /g')"
notes_ls="$( { dce client-probe ls -1 /mnt/rs/notes 2>&1 || true; } | clean | tr '\n' ' ' | sed 's/  */ /g')"
cat_ok="$( { dce client-probe cat /mnt/rs/notes/hello.txt 2>/dev/null || true; } | clean | tr -d '\r\n')"

grep -qx 'notes' <<<"$(dce client-probe ls -1 /mnt/rs 2>/dev/null)" \
  && add_check A1-list-root pass "notes present" \
  || add_check A1-list-root fail "root listing = [$root_ls]"
grep -qx 'hello.txt' <<<"$(dce client-probe ls -1 /mnt/rs/notes 2>/dev/null)" \
  && add_check A1-list-notes pass "hello.txt present" \
  || add_check A1-list-notes fail "notes listing = [$notes_ls]"
[ "$cat_ok" = "hello world" ] \
  && add_check A1-read pass "read hello world" \
  || add_check A1-read fail "cat = [$cat_ok]"
dce curl-probe curl -sS -H "Authorization: Bearer ${TOKEN}" "$S/notes/" | jq -e '.items["fusefile.txt"]' >/dev/null 2>&1 \
  && add_check A1-write pass "fusefile.txt written" \
  || add_check A1-write fail "fusefile.txt not written"

log "--- checks ---"
jq -r '.[] | "\(.status)\t\(.id)\t\(.observed)"' <<<"$checks" | tee -a "$LOG"
jq -n --argjson checks "$checks" '{client:"remotestorage-fuse",phase:"A1",pin:"'"$PIN"'",checks:$checks}' > "$OUT/result.json"
log "wrote $OUT/result.json (artifacts in $ART)"
# Client is known-incompatible; exit 0 so the evidence run is not treated as a harness error.
