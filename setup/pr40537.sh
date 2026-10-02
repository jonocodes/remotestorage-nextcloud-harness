#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

origin="${NC_CORS_ORIGIN:-http://origin}"
occ config:system:set cors.allowed-domains 0 --value="$origin" >/dev/null
occ config:system:set cors.allow-user-domains --value=false --type=boolean >/dev/null

echo "pr40537 variant: cors.allowed-domains=${origin}"
