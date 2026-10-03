#!/usr/bin/env bash
# Records the lifetime of every app token Nextcloud holds after the browser
# probes ran (T15's WebAppPassword token in particular). `occ
# user:auth-tokens:list` does not show expiry, so read oc_authtoken directly.
set -euo pipefail
cd "$(dirname "$0")/.."

out="results/${NC_VERSION}-${VARIANT}-tokens.json"
docker compose exec -T -u www-data nextcloud php -r '
  $db = new PDO("sqlite:/var/www/html/data/nextcloud.db");
  $rows = [];
  foreach ($db->query("SELECT type, name, last_activity, expires FROM oc_authtoken ORDER BY id") as $r) {
    $expires = $r["expires"] === null ? null : (int) $r["expires"];
    $rows[] = [
      "type" => (int) $r["type"],
      "name" => preg_replace("/ Mozilla.*/", "", $r["name"]),
      "last_activity" => (int) $r["last_activity"],
      "expires" => $expires,
      "lifetime_seconds" => $expires === null ? null : $expires - (int) $r["last_activity"],
    ];
  }
  echo json_encode($rows, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
' > "$out"
echo "token lifetimes written to ${out}"
