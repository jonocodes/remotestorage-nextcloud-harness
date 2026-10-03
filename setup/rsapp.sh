#!/usr/bin/env bash
# Installs the remoteStorage app (jonocodes/nextcloud-remotestorage) from a
# local checkout (RS_APP_DIR) and enables it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

app_dir="${RS_APP_DIR:-../nextcloud-remotestorage}"
[ -f "${app_dir}/appinfo/info.xml" ] || { echo "RS_APP_DIR=${app_dir} is not the app checkout" >&2; exit 1; }

tmp="$(mktemp -d)"
tar -C "$app_dir" --exclude=.git --exclude=vendor --exclude=build --exclude=tests -cf - . | tar -C "$tmp" -xf -
docker compose exec -T nextcloud rm -rf /var/www/html/custom_apps/remotestorage
docker compose cp "$tmp" nextcloud:/var/www/html/custom_apps/remotestorage >/dev/null
docker compose exec -T nextcloud chown -R www-data:www-data /var/www/html/custom_apps/remotestorage
rm -rf "$tmp"
occ app:enable remotestorage >/dev/null

version="$(occ app:list --output=json | jq -r '.enabled.remotestorage')"
commit="$(git -C "$app_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty="$(git -C "$app_dir" status --porcelain 2>/dev/null | grep -q . && echo "+dirty" || true)"
echo "${version} ${commit}${dirty}" > "results/app/${NC_VERSION}-${VARIANT}-app-version.txt"
echo "rsapp: remotestorage ${version} (${commit}${dirty}) enabled"
