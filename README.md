# remoteStorage.js × Nextcloud WebDAV test harness; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Answers one question: **can remoteStorage.js sync against stock Nextcloud WebDAV, and if; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
not, exactly what is missing?**; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Provenance: this harness implements [`PLAN.md`](PLAN.md), "remoteStorage.js × Nextcloud:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
History and Test Plan" (Sep 30 2026). It holds the history, requirements R1–R7, test cases; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
T1–T15, variants, runbook and reporting targets. [`REPORT.md`](REPORT.md) reports the; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
results.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
It is standalone: nothing here is part of remoteStorage.js.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
A second, parallel track, [`PLAN-app.md`](PLAN-app.md), builds a small Nextcloud app that makes; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Nextcloud a full remoteStorage server, so existing remoteStorage apps work unchanged:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
[jonocodes/nextcloud-remotestorage](https://github.com/jonocodes/nextcloud-remotestorage). Its; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
integration cases live in `app/` (run with `RS_APP_DIR=../nextcloud-remotestorage ./app/run.sh`); retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
and it will be reported separately.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`results/` is committed on purpose. It holds the evidence `REPORT.md` cites, from run 6 on; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
2026-10-02, plus `results/runs/run1–6.tsv`, the per-run status snapshots that back the; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
reproducibility claim. Re-running `./run.sh` overwrites it, so `git diff results/` shows; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
any behaviour change. Session cookie values in the raw header captures are redacted; they; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
came from throwaway containers.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## What it tests; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Server-side cases (T1–T10) run with `curl` in a container and cover R1–R4: recursive folder; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
ETags, ETag consistency, conditional writes and PROPFIND listing fidelity.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Browser cases (T11–T15) run in headless Chromium from a second origin and cover R5 (CORS,; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
including `Access-Control-Expose-Headers: ETag`) and R6 (connect from the browser: Login Flow v2 in T14, WebAppPassword's popup flow in T15).; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
R7 (scoping) is a known gap, recorded not tested.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## Quickstart; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```sh; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
git clone https://github.com/jonocodes/remotestorage-nextcloud-harness.git; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
cd remotestorage-nextcloud-harness; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
./run.sh                      # default matrix: 35 stock, 35 webapppassword, 34 stock, 34 webapppassword; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
VERSIONS=35 VARIANTS=stock ./run.sh; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Requires Docker with Compose v2 and network access to pull `nextcloud`, `caddy` and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`mcr.microsoft.com/playwright` images.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Results land in `results/<version>-<variant>.json` (one JSON object per case) and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`results/<version>-<variant>-nextcloud.log`, plus `-tokens.json` with app-token lifetimes.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## Layout; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| Path | Role |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| --- | --- |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `PLAN.md` | the spec: history, requirements, test cases, runbook, reporting targets |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `REPORT.md` | results and verdict |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `PLAN-app.md` | second track: a thin Nextcloud app that makes Nextcloud a remoteStorage server ([jonocodes/nextcloud-remotestorage](https://github.com/jonocodes/nextcloud-remotestorage)); spike and build results |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `app/` | integration cases for the real app (`app/run.sh`, `app/probe.sh`, `app/snapshot.sh`; browser cases in `runner/app.spec.ts`); results in `results/app/` |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `REPORT-app.md` | report on the remoteStorage app (draft) |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `compose.nginx.yaml`, `docker/nginx/` | nginx + php-fpm variants: Nextcloud's official config, and with the WebFinger rewrite |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `docker/api-test-suite/` | the community server suite, pinned (AT11), and its documented false positives |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `spike/` | throwaway spike app `rsspike` and its checks (`spike/run.sh`, `spike/probe.sh`); results in `results/spike/` |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `explore/` | third track: exploratory testing against real third-party remoteStorage clients — plan [`explore/PLAN-explore.md`](explore/PLAN-explore.md); run scripts in `explore/clients/`, evidence in `explore/sessions/`; the findings report lives in the app repo (`TESTING.md`); retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `compose.yaml` | `nextcloud`, `origin` (probe page), `curl-probe`, `runner` and `client-probe` (third-party clients) services |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `run.sh` | matrix loop: reset, up, wait, setup, curl probes, browser probes, token lifetimes, collect |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `setup/` | per-variant Nextcloud configuration via `occ` |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `probes/curl/` | T1–T10, one script per case, JSON on stdout; `cors-headers.sh` captures raw CORS headers for every variant |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `origin/` | Caddy-served `probe.html`; the browser's origin |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `runner/` | Playwright spec for T11–T15, baked into a pinned Playwright image |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `docker/curl-probe/` | Alpine + curl + xmllint + jq |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `scripts/` | `wait-for-nextcloud.sh`, `summary.sh` (matrix), `token-lifetimes.sh` (reads `oc_authtoken` expiry) |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `docker/pr40537/` | experimental image for the CORS-on-DAV pull request |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `results/` | machine-readable results, fixtures and logs |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## Variants; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| Variant | What it is |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| --- | --- |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `stock` | `nextcloud:<version>-apache`, no extra apps |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `webapppassword` | stock plus the [WebAppPassword](https://apps.nextcloud.com/apps/webapppassword) app, with this harness's origin allow-listed via `occ config:app:set webapppassword origins` |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| `pr40537` | experimental; the DAV-relevant subset of [PR #40537](https://github.com/nextcloud/server/pull/40537) applied as a patch to `nextcloud:28-apache`, configured with `occ config:system:set cors.allowed-domains 0`. The branch is based on 28.0.0 dev, not current master, and the PR as written does not run: `apps/dav/lib/Server.php` lacks its `OCP` imports and calls `get(IUserSession)`, an undefined constant. The variant image fixes both. Not in the default matrix. |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Variants get an idempotent setup script in `setup/`. Adding one is one script.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## Latest local run (2026-10-02); retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Nextcloud 35.0.1 and 34.0.4, plus the PR variant on 28.0.14.1. Three consecutive full runs; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
produced identical statuses for all 70 case-results, and the key findings were re-checked by; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
hand with browser-faithful `curl` requests. T12's criterion was amended in the plan; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
(DELETE never carries an ETag); run 5 under the amended spec matched runs 1–3 exactly, and run 6 added T15 with T1–T14 unchanged. Regenerate with `./scripts/summary.sh`;; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
the full write-up is in [`REPORT.md`](REPORT.md).; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| Case | 28/pr40537 | 34/stock | 34/webapppassword | 35/stock | 35/webapppassword |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
|---|---|---|---|---|---|; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| T1–T10 (R1–R4) | pass | pass | pass | pass | pass |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| T11 PROPFIND | pass | fail | pass | fail | pass |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| T12 PUT/GET/DELETE + ETag | pass | fail | pass | fail | pass |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| T13 stale If-Match | pass | fail | pass | fail | pass |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| T14 login flow v2 | fail | fail | fail | fail | fail |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
| T15 WebAppPassword popup connect | fail | fail | pass | fail | pass |; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
T12 checks that PUT/GET/DELETE succeed and that PUT and GET expose `ETag` (plan T12,; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
amended: Nextcloud sends no ETag on DELETE at all, and remoteStorage.js never reads one).; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Findings:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
- **R1–R4 pass on stock Nextcloud.** Recursive folder ETags change on create, overwrite and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  delete, including the root, and on the first read after PUT returns (~170–220 ms including; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  the request). Siblings are untouched. GET `ETag` equals the parent listing's `getetag`; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  (strong, quoted). `If-Match`/`If-None-Match: *` return 412 without writing. Depth-1; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  PROPFIND returns complete metadata. Fixtures in `results/fixtures/`.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
- **R5 fails on stock, passes with WebAppPassword.** Stock blocks every cross-origin DAV call; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  with `TypeError: Failed to fetch` while a control `GET /status.php` from the same page; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  returns 200, so the failure is CORS, not reachability: the credential-less preflight gets; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  401 with no CORS headers. With WebAppPassword (origins set via; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  `occ config:app:set webapppassword origins`) T11–T13 pass: PROPFIND, PUT/GET/DELETE and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  `If-Match` all work, and the page can read `ETag` on PUT and GET responses. Origins not on; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  WebAppPassword's list are refused at the preflight.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
- **R6: Login Flow v2 fails everywhere; WebAppPassword's popup flow passes.** The initial; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  `POST /index.php/login/v2` from another origin is blocked on stock and on WebAppPassword,; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  whose CORS covers WebDAV routes only (T14; upstream:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  [nextcloud/server#34898](https://github.com/nextcloud/server/issues/34898)).; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  WebAppPassword's own connect flow needs no CORS: a popup to; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  `/index.php/apps/webapppassword/?target-origin=<origin>` logs in and `postMessage`s a token; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  to the opener. On 34 and 35 the token works for a cross-origin PROPFIND and a foreign; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  origin gets 403 (T15). Tokens expire after exactly 86 400 s with no refresh, so the user; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  reconnects daily.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
- **PR #40537 is stale and broken as written.** It is still a draft, its branch is based on; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  28.0.0 dev (running it against 35 trips the one-major-version upgrade guard), and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  `apps/dav/lib/Server.php` uses an undefined `IUserSession` constant. With the DAV subset; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  applied to 28.0.14.1 and those fixes made, it matches WebAppPassword on T11–T14. Its preflight; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  answers `Access-Control-Allow-Origin: *` for any origin; only the actual response checks; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  the allow-list.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
- **Verdict inputs.** Option A is viable on a Nextcloud whose admin can enable DAV CORS; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  (WebAppPassword today, PR #40537 once rebased and fixed). On WebAppPassword servers,; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  connect works through its popup flow, with app-password paste as the fallback. Option B does not depend on CORS and can rely on the recursive ETags; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  that pass everywhere, at the cost of running a credential-holding proxy.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Open questions from the plan that this run answers: PR #40537 is still a draft and does not; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
build against current Nextcloud; WebAppPassword's config key is the app value `origins`, and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
it exposes `ETag` on PUT/GET; folder ETag propagation did not lag on first read; the default; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
matrix is the latest two majors (35, 34) × `stock` and `webapppassword`.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
### Origins: one deliberate deviation; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
The plan names the browser origin `http://app.localhost:8081` and the server; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`http://nc.localhost:8080`. Browsers hard-code every `*.localhost` name to loopback, so a; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
browser inside a container would never see those ports; making it work requires host; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
networking or non-loopback names.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
This harness keeps the plan's ports for humans (`http://app.localhost:8081`,; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`http://nc.localhost:8080` work from the host) but the automated browser runs on the compose; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
network and uses the service names: origin `http://origin`, API `http://nextcloud`. They are; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
still different origins, so CORS enforcement is identical; only the literal origin string; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
differs, and `setup/webapppassword.sh` allow-lists `http://origin` accordingly.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
The app suite (`app/run.sh`) is the exception: the remoteStorage app accepts plain-http OAuth; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
redirect URIs only on loopback hosts, so its browser tests load the origin as; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`http://localhost:8081`. The `loopback` service (Caddy, `origin/loopback.Caddyfile`) shares the; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
runner's network namespace and forwards that port to `origin`. The `explore/` browser clients; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
go through the same proxy on their own ports, so their origins stay distinct:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
My Favorite Drinks `http://localhost:8082`, RS Inspektor `:8084`.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## Result format; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`results/<version>-<variant>.json` is an array of:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```json; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
{; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "id": "T1",; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "variant": "webapppassword",; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "nextcloud_version": "35",; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "status": "pass",; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "expected": "all three ETags change",; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "observed": "root, a/, a/b/ all changed",; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  "evidence": { "etags": { "before": {}, "after": {} } }; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
}; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
`status` is `pass`, `fail` (Nextcloud behaviour) or `error` (harness bug). Raw headers and; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
PROPFIND bodies are kept in `results/fixtures/<version>-<variant>/`.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Re-run a single non-pass case by running its probe again:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```sh; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
docker compose exec -T \; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  -e VARIANT=stock -e NC_VERSION=35 -e RESULTS_DIR=/harness/results \; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  curl-probe bash /harness/probes/curl/t04.sh; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Browser cases:; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```sh; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
docker compose exec -T \; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  -e VARIANT=stock -e NC_VERSION=35 \; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
  runner npx playwright test --grep T11; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
```; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
## Runbook (for an LLM or a human); retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
1. Pick the matrix (see Quickstart) and run `./run.sh`.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
2. Read `results/*.json`. For every non-pass, re-run the case once.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
3. `error` means fix the harness and re-run. `fail` means keep the raw headers and do not; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
   change Nextcloud config beyond what the variant defines.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
4. Stop and ask a human if: the same case is `error` three times; a variant needs a setting; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
   not in its setup script; Login Flow approval cannot be automated after two attempts.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
5. Write the report: results matrix (case × version × variant), one paragraph per failure; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
   with evidence, then the verdict on Option A (client-side backend) vs Option B (Armadietto; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
   WebDAV store router). Posting targets are listed in the plan.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
Never loosen pass criteria, run against anything other than the local container, or use real; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
credentials.; retired clients are listed in [`ARCHIVE.md`](ARCHIVE.md) |
