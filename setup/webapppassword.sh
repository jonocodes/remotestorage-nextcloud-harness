#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if ! occ app:install webapppassword >/dev/null 2>&1; then
  echo "occ app:install failed; falling back to the release tarball" >&2
  app_version="${WEBAPPPASSWORD_VERSION:-26.8.0}"
  tmp="$(mktemp -d)"
  curl -fsSL \
    "https://github.com/digital-blueprint/webapppassword/releases/download/v${app_version}/webapppassword.tar.gz" \
    -o "${tmp}/webapppassword.tar.gz"
  docker compose cp "${tmp}/webapppassword.tar.gz" nextcloud:/tmp/webapppassword.tar.gz
  docker compose exec -T nextcloud sh -c '
    set -e
    rm -rf /tmp/webapppassword && mkdir -p /tmp/webapppassword
    tar -xzf /tmp/webapppassword.tar.gz -C /tmp/webapppassword
    info="$(find /tmp/webapppassword -path "*/appinfo/info.xml" | head -n1)"
    src="$(dirname "$(dirname "$info")")"
    rm -rf /var/www/html/custom_apps/webapppassword
    mv "$src" /var/www/html/custom_apps/webapppassword
    chown -R www-data:www-data /var/www/html/custom_apps/webapppassword
  '
  rm -rf "$tmp"
fi

occ app:enable webapppassword >/dev/null

origin="${NC_CORS_ORIGIN:-http://origin}"
occ config:app:set webapppassword origins --value="$origin" >/dev/null
occ config:app:set webapppassword files_sharing_origins --value="$origin" >/dev/null || true
occ config:app:set webapppassword preview_origins --value="$origin" >/dev/null || true

echo "webapppassword variant: enabled, origins=${origin}"
