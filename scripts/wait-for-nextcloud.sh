#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

deadline=$(( SECONDS + 300 ))
until docker compose exec -T -u www-data nextcloud php occ status 2>/dev/null | grep -q 'installed: true'; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "timed out after 300s waiting for Nextcloud to install" >&2
    docker compose logs --tail=50 nextcloud >&2 || true
    exit 1
  fi
  sleep 5
done

for service in curl-probe runner; do
  until docker compose exec -T "$service" true >/dev/null 2>&1; do
    sleep 2
  done
done

until docker compose exec -T curl-probe curl -fsS -o /dev/null http://nextcloud/status.php 2>/dev/null; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "timed out after 300s waiting for Nextcloud HTTP to answer" >&2
    exit 1
  fi
  sleep 2
done

echo "Nextcloud reports installed: true and serves status.php"
