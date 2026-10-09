# Container for third-party remoteStorage clients (PLAN-explore.md).
# Runs on the compose network so `nextcloud` resolves and WebFinger works.
# Node for rs-backup / rs.js CLI clients, PHP for remote-storage-uploader.
FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config git jq ca-certificates curl \
      php-cli php-curl php-xml \
    && rm -rf /var/lib/apt/lists/*

# rs-backup / rs-restore (A2). rs-backup 1.10.0 pulls webfinger.js ^2.7.1,
# which resolves to 2.8.2 — ESM-only, and rs-backup loads it with require(),
# so it throws on Node 20. Pin the last CJS webfinger.js.
COPY package.json /opt/rs-backup/package.json
RUN cd /opt/rs-backup \
    && npm install --no-audit --no-fund \
    && ln -s /opt/rs-backup/node_modules/.bin/rs-backup /usr/local/bin/rs-backup \
    && ln -s /opt/rs-backup/node_modules/.bin/rs-restore /usr/local/bin/rs-restore

WORKDIR /harness
CMD ["sleep", "infinity"]
