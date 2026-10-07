#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export NC_USER="${NC_USER:-rstest}"
export NC_PASS="${NC_PASS:-rstest-pass}"
export NC_ADMIN_USER="${NC_ADMIN_USER:-admin}"
export NC_ADMIN_PASSWORD="${NC_ADMIN_PASSWORD:-admin}"
export NC_CORS_ORIGIN="${NC_CORS_ORIGIN:-http://localhost}"

read -r -a VERSIONS <<< "${VERSIONS:-35 34}"
read -r -a VARIANTS <<< "${VARIANTS:-stock webapppassword}"
read -r -a CASES <<< "${CASES:-}"

mkdir -p results

overall=0
for version in "${VERSIONS[@]}"; do
  for variant in "${VARIANTS[@]}"; do
    export NC_VERSION="$version"
    export VARIANT="$variant"
    export NC_IMAGE="${NC_IMAGE_OVERRIDE:-nextcloud:${version}-apache}"

    echo
    echo "=== Nextcloud ${version} / ${variant} ==="

    if [ "$variant" = "pr40537" ]; then
      export NC_IMAGE="rs-nc-pr40537:${version}"
      docker build -f docker/pr40537/Dockerfile \
        --build-arg "NC_BASE_VERSION=${version}" \
        -t "$NC_IMAGE" .
    fi

    docker compose down -v --remove-orphans
    docker compose build curl-probe runner
    docker compose up -d
    ./scripts/wait-for-nextcloud.sh
    bash setup/common.sh
    bash "setup/${variant}.sh"

    docker compose exec -T \
      -e "VARIANT=${variant}" -e "NC_VERSION=${version}" \
      -e "RESULTS_DIR=/harness/results" -e "NC_CORS_ORIGIN=${NC_CORS_ORIGIN}" \
      curl-probe bash /harness/probes/curl/cors-headers.sh \
      || overall=1

    if [ "${#CASES[@]}" -eq 0 ] || printf '%s\n' "${CASES[@]}" | grep -qE '^T([1-9]|10)$'; then
      docker compose exec -T \
        -e "VARIANT=${variant}" -e "NC_VERSION=${version}" \
        -e "RESULTS_DIR=/harness/results" \
        curl-probe bash /harness/probes/curl/run-all.sh "/harness/results/${version}-${variant}-curl.json" \
        || overall=1
    fi

    if [ "${#CASES[@]}" -eq 0 ] || printf '%s\n' "${CASES[@]}" | grep -qE '^T1[1-5]$'; then
      docker compose exec -T \
        -e "VARIANT=${variant}" -e "NC_VERSION=${version}" \
        runner npx playwright test --grep 'T1[1-5]' \
        || overall=1
      ./scripts/token-lifetimes.sh || overall=1
    fi

    for part in curl browser; do
      file="results/${version}-${variant}-${part}.json"
      if [ ! -s "$file" ]; then
        echo '[]' > "$file"
      fi
    done

    jq -s 'add' \
      "results/${version}-${variant}-curl.json" \
      "results/${version}-${variant}-browser.json" \
      > "results/${version}-${variant}.json"

    docker compose logs nextcloud > "results/${version}-${variant}-nextcloud.log" 2>&1 || true

    echo "--- ${version}-${variant} ---"
    jq -r '.[] | "\(.id)\t\(.status)\t\(.observed)"' "results/${version}-${variant}.json"
  done
done

exit "$overall"
