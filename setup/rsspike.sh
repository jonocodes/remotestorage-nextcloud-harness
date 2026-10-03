#!/usr/bin/env bash
# Throwaway spike variant for PLAN-app.md S1–S4: installs spike/rsspike and
# gives it one token in app config.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

docker compose exec -T nextcloud rm -rf /var/www/html/custom_apps/rsspike
docker compose cp spike/rsspike nextcloud:/var/www/html/custom_apps/rsspike
docker compose exec -T nextcloud chown -R www-data:www-data /var/www/html/custom_apps/rsspike
occ app:enable rsspike >/dev/null

occ config:app:set rsspike token --value="${RS_TOKEN:-spike-token-notes-rw}" >/dev/null
occ config:app:set rsspike user --value="${NC_USER}" >/dev/null
occ config:app:set rsspike scope --value="${RS_SCOPE:-notes:rw public:rw}" >/dev/null

echo "rsspike variant: enabled, scope=${RS_SCOPE:-notes:rw public:rw}"
