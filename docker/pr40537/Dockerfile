ARG NC_BASE_VERSION=28
FROM nextcloud:${NC_BASE_VERSION}-apache

ARG PR_NUMBER=40537

USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl patch; \
    curl -fsSL "https://github.com/nextcloud/server/pull/${PR_NUMBER}.diff" -o /tmp/pr.diff; \
    awk '/^diff --git / { \
           skip = !($0 ~ / b\/apps\/dav\/composer\/composer\/autoload_(classmap|static)\.php$/ || \
                    $0 ~ / b\/apps\/dav\/lib\/Connector\/Sabre\/CorsPlugin\.php$/ || \
                    $0 ~ / b\/apps\/dav\/lib\/Connector\/Sabre\/ServerFactory\.php$/ || \
                    $0 ~ / b\/apps\/dav\/lib\/Server\.php$/ || \
                    $0 ~ / b\/lib\/private\/legacy\/OC_Response\.php$/ || \
                    $0 ~ / b\/lib\/public\/Util\.php$/) \
         } skip == 0 { print }' \
      /tmp/pr.diff > /tmp/pr-filtered.diff; \
    cd /usr/src/nextcloud; \
    patch -p1 --forward --fuzz=5 < /tmp/pr-filtered.diff; \
    sed -i 's/get(IUserSession)/get(\\OCP\\IUserSession::class)/; s/get(IConfig::class)/get(\\OCP\\IConfig::class)/' apps/dav/lib/Server.php; \
    ! grep -q 'get(IUserSession)' apps/dav/lib/Server.php; \
    ! grep -q 'get(IConfig::class)' apps/dav/lib/Server.php; \
    test -f apps/dav/lib/Connector/Sabre/CorsPlugin.php; \
    grep -q CorsPlugin apps/dav/lib/Server.php; \
    grep -q 'function setCorsHeaders' lib/private/legacy/OC_Response.php; \
    grep -q 'isSameDomain' lib/public/Util.php; \
    ! find . -name '*.rej' | grep -q .; \
    rm -f /tmp/pr.diff /tmp/pr-filtered.diff; \
    apt-get purge -y curl patch; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*
