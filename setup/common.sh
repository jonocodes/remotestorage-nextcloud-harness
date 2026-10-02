#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if ! occ user:add --password-from-env "$NC_USER" >/dev/null 2>&1; then
  occ user:resetpassword --password-from-env "$NC_USER" >/dev/null
fi
occ user:enable "$NC_USER" >/dev/null 2>&1 || true

code="$(mkcol "/remote.php/dav/files/${NC_USER}/remotestorage")"
if [ "$code" != "201" ] && [ "$code" != "405" ]; then
  echo "could not create /remotestorage (HTTP ${code})" >&2
  exit 1
fi

echo "common setup done: user=${NC_USER} folder=/remote.php/dav/files/${NC_USER}/remotestorage"
