#!/usr/bin/env bash
# AT11: runs the remoteStorage community's server test suite (pinned image,
# docker/api-test-suite) against the current stack and prints one JSON result.
# Usage: app/api-test-suite.sh <raw-output-file>
set -uo pipefail
cd "$(dirname "$0")/.."
raw="$1"
# The suite needs an account with no data in it (not the probes' user) and a second account.
for u in rssuite rsother; do
  docker compose exec -T -u www-data -e OC_PASS=suite-pass-1234 nextcloud php occ user:add --password-from-env "$u" >/dev/null 2>&1 || true
done
tok() { docker compose exec -T -u www-data nextcloud php occ remotestorage:token:issue rssuite "$1" api-test-suite | tr -d '\r\n'; }
config="$(mktemp)"
cat > "$config" <<YAML
storage_base_url: http://nextcloud/remote.php/dav/files/rssuite/remoteStorage
storage_base_url_other: http://nextcloud/remote.php/dav/files/rsother/remoteStorage
category: api-test
token: $(tok 'api-test:rw')
read_only_token: $(tok 'api-test:r')
root_token: $(tok '*:rw')
YAML
docker build -q -t rs-nc-api-test-suite docker/api-test-suite >/dev/null
network="$(docker inspect "$(docker compose ps -q nextcloud)" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
docker run --rm --network "$network" -v "$config:/suite/config.yml:ro" rs-nc-api-test-suite 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -v 'rs_[A-Za-z0-9]\{43\}' \
  | sed -E 's/(oc_sessionPassphrase|oc[a-z0-9]{10,12}|nc_session_id)=[^;", ]+/\1=<redacted>/g' > "$raw"
rm -f "$config"

summary="$(grep -E '^[0-9]+ tests, ' "$raw" | tail -n1)"
# "<describe block>|<test>" for every FAIL/ERROR line.
failing="$(awk '/^[A-Za-z][^ ]*::/ && !/ (request failed|warning:)/ {block=$0}
  / (FAIL|ERROR) \(/ {name=$0; sub(/^ +/, "", name); sub(/ +(FAIL|ERROR) \(.*$/, "", name); print block "|" name}' "$raw" | sort -u)"
known="$(grep -v '^#' docker/api-test-suite/known-false-positives.txt | cut -d'|' -f1,2 | sort -u)"
unexpected="$(comm -23 <(printf '%s\n' "$failing" | grep -v '^$') <(printf '%s\n' "$known"))"
status=pass
{ [ -z "$summary" ] || [ -n "$unexpected" ]; } && status=fail
jq -n --arg summary "${summary:-no summary (suite did not run)}" --arg failing "$failing" \
  --arg unexpected "$unexpected" --arg status "$status" \
  '{id: "AT11", check: "remotestorage/api-test-suite: every failing test is a documented false positive",
    expected: "no failures outside docker/api-test-suite/known-false-positives.txt",
    observed: ($summary + (if $unexpected != "" then "; unexpected: " + ($unexpected | split("\n") | join("; ")) else "" end)
               + (if $failing != "" then "; known false positives failing: " + ([$failing | split("\n")[] | select(. as $f | ($unexpected | split("\n") | index($f)) == null)] | join("; ")) else "" end)),
    status: $status}'
