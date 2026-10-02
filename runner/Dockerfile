ARG PLAYWRIGHT_VERSION=1.63.0
FROM mcr.microsoft.com/playwright:v${PLAYWRIGHT_VERSION}-noble

ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

WORKDIR /harness/runner

COPY package.json /harness/runner/package.json
RUN npm install --no-package-lock "@playwright/test@${PLAYWRIGHT_VERSION}"

COPY . /harness/runner
