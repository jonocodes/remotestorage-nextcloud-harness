# remoteStorage.js × Nextcloud WebDAV test harness

Answers one question: **can remoteStorage.js sync against stock Nextcloud WebDAV, and if
not, exactly what is missing?**

Provenance: this harness implements [`PLAN.md`](PLAN.md), "remoteStorage.js × Nextcloud:
History and Test Plan" (Sep 30 2026). It holds the history, requirements R1–R7, test cases
T1–T15, variants, runbook and reporting targets. [`REPORT.md`](REPORT.md) reports the
results.

It is standalone: nothing here is part of remoteStorage.js.

A second, parallel track, [`PLAN-app.md`](PLAN-app.md), plans a small Nextcloud app that makes
Nextcloud a full remoteStorage server, so existing remoteStorage apps work unchanged. It will
be reported separately.

`results/` is committed on purpose. It holds the evidence `REPORT.md` cites, from run 6 on
2026-10-02, plus `results/runs/run1–6.tsv`, the per-run status snapshots that back the
reproducibility claim. Re-running `./run.sh` overwrites it, so `git diff results/` shows
any behaviour change. Session cookie values in the raw header captures are redacted; they
came from throwaway containers.

## What it tests

Server-side cases (T1–T10) run with `curl` in a container and cover R1–R4: recursive folder
ETags, ETag consistency, conditional writes and PROPFIND listing fidelity.

Browser cases (T11–T15) run in headless Chromium from a second origin and cover R5 (CORS,
including `Access-Control-Expose-Headers: ETag`) and R6 (connect from the browser: Login Flow v2 in T14, WebAppPassword's popup flow in T15).
R7 (scoping) is a known gap, recorded not tested.

## Quickstart

```sh
git clone https://github.com/jonocodes/remotestorage-nextcloud-harness.git
cd remotestorage-nextcloud-harness
./run.sh                      # default matrix: 35 stock, 35 webapppassword, 34 stock, 34 webapppassword
VERSIONS=35 VARIANTS=stock ./run.sh
```

Requires Docker with Compose v2 and network access to pull `nextcloud`, `caddy` and
`mcr.microsoft.com/playwright` images.

Results land in `results/<version>-<variant>.json` (one JSON object per case) and
`results/<version>-<variant>-nextcloud.log`, plus `-tokens.json` with app-token lifetimes.

## Layout

| Path | Role |
| --- | --- |
| `PLAN.md` | the spec: history, requirements, test cases, runbook, reporting targets |
| `REPORT.md` | results and verdict |
| `PLAN-app.md` | second track: a thin Nextcloud app that makes Nextcloud a remoteStorage server (planned, not built) |
| `compose.yaml` | `nextcloud`, `origin` (probe page), `curl-probe` and `runner` services |
| `run.sh` | matrix loop: reset, up, wait, setup, curl probes, browser probes, token lifetimes, collect |
| `setup/` | per-variant Nextcloud configuration via `occ` |
| `probes/curl/` | T1–T10, one script per case, JSON on stdout; `cors-headers.sh` captures raw CORS headers for every variant |
| `origin/` | Caddy-served `probe.html`; the browser's origin |
| `runner/` | Playwright spec for T11–T15, baked into a pinned Playwright image |
| `docker/curl-probe/` | Alpine + curl + xmllint + jq |
| `scripts/` | `wait-for-nextcloud.sh`, `summary.sh` (matrix), `token-lifetimes.sh` (reads `oc_authtoken` expiry) |
| `docker/pr40537/` | experimental image for the CORS-on-DAV pull request |
| `results/` | machine-readable results, fixtures and logs |

## Variants

| Variant | What it is |
| --- | --- |
| `stock` | `nextcloud:<version>-apache`, no extra apps |
| `webapppassword` | stock plus the [WebAppPassword](https://apps.nextcloud.com/apps/webapppassword) app, with this harness's origin allow-listed via `occ config:app:set webapppassword origins` |
| `pr40537` | experimental; the DAV-relevant subset of [PR #40537](https://github.com/nextcloud/server/pull/40537) applied as a patch to `nextcloud:28-apache`, configured with `occ config:system:set cors.allowed-domains 0`. The branch is based on 28.0.0 dev, not current master, and the PR as written does not run: `apps/dav/lib/Server.php` lacks its `OCP` imports and calls `get(IUserSession)`, an undefined constant. The variant image fixes both. Not in the default matrix. |

Variants get an idempotent setup script in `setup/`. Adding one is one script.

## Latest local run (2026-10-02)

Nextcloud 35.0.1 and 34.0.4, plus the PR variant on 28.0.14.1. Three consecutive full runs
produced identical statuses for all 70 case-results, and the key findings were re-checked by
hand with browser-faithful `curl` requests. T12's criterion was amended in the plan
(DELETE never carries an ETag); run 5 under the amended spec matched runs 1–3 exactly, and run 6 added T15 with T1–T14 unchanged. Regenerate with `./scripts/summary.sh`;
the full write-up is in [`REPORT.md`](REPORT.md).

| Case | 28/pr40537 | 34/stock | 34/webapppassword | 35/stock | 35/webapppassword |
|---|---|---|---|---|---|
| T1–T10 (R1–R4) | pass | pass | pass | pass | pass |
| T11 PROPFIND | pass | fail | pass | fail | pass |
| T12 PUT/GET/DELETE + ETag | pass | fail | pass | fail | pass |
| T13 stale If-Match | pass | fail | pass | fail | pass |
| T14 login flow v2 | fail | fail | fail | fail | fail |
| T15 WebAppPassword popup connect | fail | fail | pass | fail | pass |

T12 checks that PUT/GET/DELETE succeed and that PUT and GET expose `ETag` (plan T12,
amended: Nextcloud sends no ETag on DELETE at all, and remoteStorage.js never reads one).

Findings:

- **R1–R4 pass on stock Nextcloud.** Recursive folder ETags change on create, overwrite and
  delete, including the root, and on the first read after PUT returns (~170–220 ms including
  the request). Siblings are untouched. GET `ETag` equals the parent listing's `getetag`
  (strong, quoted). `If-Match`/`If-None-Match: *` return 412 without writing. Depth-1
  PROPFIND returns complete metadata. Fixtures in `results/fixtures/`.
- **R5 fails on stock, passes with WebAppPassword.** Stock blocks every cross-origin DAV call
  with `TypeError: Failed to fetch` while a control `GET /status.php` from the same page
  returns 200, so the failure is CORS, not reachability: the credential-less preflight gets
  401 with no CORS headers. With WebAppPassword (origins set via
  `occ config:app:set webapppassword origins`) T11–T13 pass: PROPFIND, PUT/GET/DELETE and
  `If-Match` all work, and the page can read `ETag` on PUT and GET responses. Origins not on
  WebAppPassword's list are refused at the preflight.
- **R6: Login Flow v2 fails everywhere; WebAppPassword's popup flow passes.** The initial
  `POST /index.php/login/v2` from another origin is blocked on stock and on WebAppPassword,
  whose CORS covers WebDAV routes only (T14; upstream:
  [nextcloud/server#34898](https://github.com/nextcloud/server/issues/34898)).
  WebAppPassword's own connect flow needs no CORS: a popup to
  `/index.php/apps/webapppassword/?target-origin=<origin>` logs in and `postMessage`s a token
  to the opener. On 34 and 35 the token works for a cross-origin PROPFIND and a foreign
  origin gets 403 (T15). Tokens expire after exactly 86 400 s with no refresh, so the user
  reconnects daily.
- **PR #40537 is stale and broken as written.** It is still a draft, its branch is based on
  28.0.0 dev (running it against 35 trips the one-major-version upgrade guard), and
  `apps/dav/lib/Server.php` uses an undefined `IUserSession` constant. With the DAV subset
  applied to 28.0.14.1 and those fixes made, it matches WebAppPassword on T11–T14. Its preflight
  answers `Access-Control-Allow-Origin: *` for any origin; only the actual response checks
  the allow-list.
- **Verdict inputs.** Option A is viable on a Nextcloud whose admin can enable DAV CORS
  (WebAppPassword today, PR #40537 once rebased and fixed). On WebAppPassword servers,
  connect works through its popup flow, with app-password paste as the fallback. Option B does not depend on CORS and can rely on the recursive ETags
  that pass everywhere, at the cost of running a credential-holding proxy.

Open questions from the plan that this run answers: PR #40537 is still a draft and does not
build against current Nextcloud; WebAppPassword's config key is the app value `origins`, and
it exposes `ETag` on PUT/GET; folder ETag propagation did not lag on first read; the default
matrix is the latest two majors (35, 34) × `stock` and `webapppassword`.

### Origins: one deliberate deviation

The plan names the browser origin `http://app.localhost:8081` and the server
`http://nc.localhost:8080`. Browsers hard-code every `*.localhost` name to loopback, so a
browser inside a container would never see those ports; making it work requires host
networking or non-loopback names.

This harness keeps the plan's ports for humans (`http://app.localhost:8081`,
`http://nc.localhost:8080` work from the host) but the automated browser runs on the compose
network and uses the service names: origin `http://origin`, API `http://nextcloud`. They are
still different origins, so CORS enforcement is identical; only the literal origin string
differs, and `setup/webapppassword.sh` allow-lists `http://origin` accordingly.

## Result format

`results/<version>-<variant>.json` is an array of:

```json
{
  "id": "T1",
  "variant": "webapppassword",
  "nextcloud_version": "35",
  "status": "pass",
  "expected": "all three ETags change",
  "observed": "root, a/, a/b/ all changed",
  "evidence": { "etags": { "before": {}, "after": {} } }
}
```

`status` is `pass`, `fail` (Nextcloud behaviour) or `error` (harness bug). Raw headers and
PROPFIND bodies are kept in `results/fixtures/<version>-<variant>/`.

Re-run a single non-pass case by running its probe again:

```sh
docker compose exec -T \
  -e VARIANT=stock -e NC_VERSION=35 -e RESULTS_DIR=/harness/results \
  curl-probe bash /harness/probes/curl/t04.sh
```

Browser cases:

```sh
docker compose exec -T \
  -e VARIANT=stock -e NC_VERSION=35 \
  runner npx playwright test --grep T11
```

## Runbook (for an LLM or a human)

1. Pick the matrix (see Quickstart) and run `./run.sh`.
2. Read `results/*.json`. For every non-pass, re-run the case once.
3. `error` means fix the harness and re-run. `fail` means keep the raw headers and do not
   change Nextcloud config beyond what the variant defines.
4. Stop and ask a human if: the same case is `error` three times; a variant needs a setting
   not in its setup script; Login Flow approval cannot be automated after two attempts.
5. Write the report: results matrix (case × version × variant), one paragraph per failure
   with evidence, then the verdict on Option A (client-side backend) vs Option B (Armadietto
   WebDAV store router). Posting targets are listed in the plan.

Never loosen pass criteria, run against anything other than the local container, or use real
credentials.
