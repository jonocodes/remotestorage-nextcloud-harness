# Can remoteStorage.js sync against Nextcloud WebDAV?

**Test report — 2026-10-02 · @Jono (harness and runs with agent assistance)**

Status: **reviewed 2026-10-02; not yet posted to the issue threads or forum.** Companion to [`PLAN.md`](PLAN.md), "remoteStorage.js ×
Nextcloud: History and Test Plan" (Sep 30 2026). Harness and raw results live in this repository,
<https://github.com/jonocodes/remotestorage-nextcloud-harness>; nothing has been posted to
the remoteStorage or Nextcloud issue threads or the forum yet.

## Summary

- **R1–R4 pass on stock Nextcloud 34 and 35.** Recursive folder ETags, ETag consistency,
  conditional writes and Depth-1 listings all behave the way remoteStorage.js sync needs.
  A Nextcloud-specific backend can rely on them.
- **R5 fails on stock and passes with WebAppPassword.** Stock rejects the browser's
  preflight with 401 and sends no `Access-Control-*` headers on any DAV response.
  WebAppPassword makes PROPFIND, GET, PUT and DELETE work from an allow-listed origin,
  exposes `ETag` on PUT and GET, and refuses origins that are not on its list. (T12's
  criterion was amended in the plan: Nextcloud sends no ETag on DELETE responses at all,
  even to same-origin `curl`, and remoteStorage.js never reads one.)
- **R6: Login Flow v2 fails everywhere, but WebAppPassword's own connect flow works.**
  The initial `POST /index.php/login/v2` from another origin is blocked on stock and on
  WebAppPassword (T14); WebAppPassword's CORS covers DAV routes only. WebAppPassword's popup
  flow (T15, added after the first runs) needs no CORS: the user logs in to Nextcloud in a
  popup, which hands a token back to the app by `postMessage`. It passes on 34 and 35, the
  token works for cross-origin DAV, and foreign origins are refused. Its tokens expire after
  24 hours with no refresh mechanism, so the user reconnects daily (a self-closing popup).
- **PR #40537 is stale and does not run as written.** It is still a draft, its branch is
  based on Nextcloud 28.0.0 dev (not current master), and `apps/dav/lib/Server.php` uses an
  undefined `IUserSession` constant and lacks its `OCP` imports. With the DAV-relevant subset
  applied to 28.0.14.1 and those fixed, it behaves like WebAppPassword on T11–T14 (T11–T13
  pass, T14 fails; T15 does not apply, as the PR has no connect flow). Its preflight
  answers `Access-Control-Allow-Origin: *` for any origin; the allow-list is only enforced
  on the actual response.
- **Verdict:** Option A is viable today on servers with WebAppPassword: it supplies both the
  DAV CORS and the connect step. Connect via its popup flow, with app-password paste as the
  fallback for a permanent credential. Option B remains the only CORS-independent route and
  can rely on the ETag behaviour verified here.
- Three consecutive full runs produced **identical statuses for all 70 case-results**, and
  the key findings were re-checked by hand with browser-faithful `curl` requests. A fifth run
  under the amended T12 criterion matched them exactly, and a sixth run with T15 added left
  T1–T14 unchanged.

## Method

The harness (this repository) runs one `docker compose` stack per variant: Nextcloud
(SQLite), a Caddy-served probe page on a second origin, an Alpine `curl`/`xmllint`/`jq`
container for T1–T10 and a Playwright 1.63 container for T11–T15. Pass/fail comes from the
scripts; the JSON in `results/` is the source of truth. `scripts/summary.sh` renders the
matrix.

Matrix and variants:

| Run | Nextcloud | Variant | Image (local podman image ID) |
| --- | --- | --- | --- |
| 35/stock | 35.0.1 | no extra apps | `nextcloud:35-apache` `05b7779142c379ddcf7` |
| 35/webapppassword | 35.0.1 | WebAppPassword (app store), origin allowed via `occ config:app:set webapppassword origins` | same |
| 34/stock | 34.0.4 | no extra apps | `nextcloud:34-apache` `8c214395f1c943e4097` |
| 34/webapppassword | 34.0.4 | as above | same |
| 28/pr40537 | 28.0.14.1 | DAV subset of PR #40537 patched in | `nextcloud:28-apache` `ca31ddddf27bb78aac1` |

Test identity: user `rstest`, storage root `/remote.php/dav/files/rstest/remotestorage/`
(`$R`), every case starts from an empty `$R`. All paths and pass criteria are exactly as
specified in the test table of [`PLAN.md`](PLAN.md). One criterion was amended in the plan itself, with the
reason recorded there: T12 originally required a readable `ETag` on the DELETE response as
well as PUT and GET. Nextcloud sends no ETag on DELETE at all, so that clause could never
pass on any server configuration and tested nothing about CORS. A run under the original
wording (run 4) failed T12 on every variant for that reason alone; see R5.

Two deliberate implementation notes:

- **Browser origin.** The plan's `http://app.localhost:8081` / `http://nc.localhost:8080`
  cannot work for a browser inside a container: browsers hard-code every `*.localhost` name
  to loopback. The automated browser uses `http://origin` and `http://nextcloud` on the
  compose network (still different origins, so CORS is enforced identically). The plan's
  ports stay published for humans. `setup/webapppassword.sh` allow-lists `http://origin`.
- **PR variant.** The PR diff is filtered to the DAV-relevant files
  (`CorsPlugin`, `ServerFactory`, `Server`, `OC_Response`, `Util`, DAV autoload maps) and
  applied to the matching 28.x image. Two fixes are applied in the image and are described
  in the PR section below.

Reproducibility: three full runs (all five configurations each) produced identical statuses
for all 70 case-results, with zero harness errors. Run 4 used T12's original wording and differed only
in T12 on 35/webapppassword, 34/webapppassword and 28/pr40537 (pass → fail). Run 5, under
the amended criterion, is identical to runs 1–3. Run 6 added T15 and left all 70 T1–T14 results unchanged; the results in this report are from run 6. T4 first-read latency ranged 171–216 ms
across all runs and variants. Raw response headers for every run are saved as
`results/<version>-<variant>-cors-headers.txt`; preflights there carry no `Authorization`
header, exactly as a browser sends them, and each file also records a non-allow-listed
origin (`http://evil.example`) and the login/v2 endpoint.

Independent check: the CORS, ETag, 412 and DELETE-ETag findings were re-tested by hand on
live 35/stock, 35/webapppassword and 28/pr40537 stacks with plain `curl` (outside the probe
scripts), and the PR claims were re-read from the upstream branch. Both agree with the
harness.

## Results

| Case | 28/pr40537 | 34/stock | 34/webapppassword | 35/stock | 35/webapppassword |
|---|---|---|---|---|---|
| T1 | pass | pass | pass | pass | pass |
| T2 | pass | pass | pass | pass | pass |
| T3 | pass | pass | pass | pass | pass |
| T4 | pass | pass | pass | pass | pass |
| T5 | pass | pass | pass | pass | pass |
| T6 | pass | pass | pass | pass | pass |
| T7 | pass | pass | pass | pass | pass |
| T8 | pass | pass | pass | pass | pass |
| T9 | pass | pass | pass | pass | pass |
| T10 | pass | pass | pass | pass | pass |
| T11 | pass | fail | pass | fail | pass |
| T12 | pass | fail | pass | fail | pass |
| T13 | pass | fail | pass | fail | pass |
| T14 | fail | fail | fail | fail | fail |
| T15 | fail | fail | pass | fail | pass |

## Findings

### R1 — Recursive folder ETags (T1–T5): pass on every variant

- T1/T2/T3: creating, overwriting and deleting `$R/a/b/c.txt` changed the ETags of `$R`,
  `$R/a/` and `$R/a/b/` in every run, on stock and WebAppPassword, on 34, 35 and the patched
  PR build.
- T4: the root ETag had already changed on the first PROPFIND after PUT returned. Observed
  first-read latency 171–216 ms including the request itself; there was never a case where a
  later read was needed. No propagation lag observed.
- T5: writing under `$R/x/` left the sibling `$R/y/` ETag untouched while the root changed.

### R2 — ETag consistency (T6): pass on every variant

GET and PROPFIND agree after quote normalization; ETags are strong and quoted, no `W/`
prefixes were seen. Example (35/stock):
`"369aad767bc902e26ad049335c530126"` from both GET `ETag` and the parent listing's
`getetag`.

### R3 — Conditional writes (T7–T9): pass on every variant

- PUT with `If-Match: "stale"` → 412 and the file body unchanged.
- PUT with `If-None-Match: *` on an existing file → 412 and unchanged.
- DELETE with `If-Match: "stale"` → 412 and the file still readable (GET 200).

### R4 — Listing mapping (T10): pass on every variant

Depth-1 PROPFIND returned exactly four responses (folder + two files + one subfolder). Each
file carried `getetag`, `getcontenttype`, `getcontentlength` and `getlastmodified`; the
subfolder carried `getetag`. The XML-to-JSON mapping used by the harness is saved as a
fixture (`results/fixtures/<version>-<variant>/t10-mapping.json`). Example mapping:

```json
{"files":[{"href":".../f1.txt","etag":"\"95eb6f795c11c1da65657a757eab0043\"",
           "contenttype":"text/plain","contentlength":"3",
           "lastmodified":"Fri, 02 Oct 2026 15:44:18 GMT"},
          {"href":".../f2.txt","etag":"\"13c4cd331c53b980f71a435cca69bac9\"",
           "contenttype":"text/plain","contentlength":"10",
           "lastmodified":"Fri, 02 Oct 2026 15:44:18 GMT"}],
 "collections":[{"href":".../sub/","etag":"\"6abfd153321d1\""}]}
```

### R5 — CORS (T11–T13): fail on stock, pass with WebAppPassword

**Stock.** The origin page reaches Nextcloud (control `GET /status.php` returns 200), but
every DAV call throws `TypeError: Failed to fetch`. The raw headers show why: the browser's
preflight (OPTIONS without credentials) is rejected with **401 Unauthorized and no
`Access-Control-*` headers**, and authenticated PROPFIND, GET, PUT and DELETE responses carry
no `Access-Control-*` headers either. The browser stops at the preflight, so the request
never reaches DAV. (`/status.php` does send `Access-Control-Allow-Origin: *`; DAV routes do
not.)

**WebAppPassword.** T11, T12 and T13 pass. Raw headers on every DAV response:

```
access-control-allow-origin: http://origin
access-control-expose-headers: etag, dav
access-control-allow-credentials: true
```

The credential-less preflight answers 204 and additionally echoes
`access-control-allow-methods: PROPFIND` and `access-control-allow-headers: authorization,depth`.
For an origin that is not on the list (`http://evil.example`) the preflight is rejected with
401 and the actual response carries no `Access-Control-Allow-Origin`, so the allow-list is
enforced at both steps. WebAppPassword 26.8.0 was installed. Functional results: PROPFIND 207;
PUT 201, GET 200, DELETE 204; `ETag` readable by the page on PUT and GET (same value,
`"93c1d0a0a85c9a7e5eff3819e3df1a77"` in the 35 run); stale `If-Match` PUT returns 412 and
the page sees it.

**T12 amendment.** The plan originally required a readable `ETag` on the DELETE response
too, and the page sees `null` there. That is not CORS hiding the header: Nextcloud sends no
`ETag` on DELETE responses at all. The same-run raw headers show none, even to same-origin
`curl`, on every variant including stock, so no CORS configuration could ever satisfy that
clause. remoteStorage.js does not need it either: after a successful DELETE,
`Sync.completePush` flushes the node and ignores the revision, and on a 412 conflict it falls
back to `'conflict'` when there is no ETag (`src/sync.ts`). The plan's T12 criterion was
therefore amended to PUT and GET, with the reason recorded in the plan; the harness still
records the DELETE ETag (always `null`) in the evidence.

Two observations for the app: `Access-Control-Expose-Headers` is exactly `etag, dav` (the
header sync depends on is covered), and the responses do not send `Vary: Origin`. The latter
is only a shared-cache concern for authenticated DAV responses, not a correctness problem in
this test.

### R6 — Connect from the browser: Login Flow v2 fails everywhere (T14); WebAppPassword's popup flow passes (T15)

**Login Flow v2 (T14).** `POST /index.php/login/v2` from the origin page throws
`TypeError: Failed to fetch` on stock and on WebAppPassword. The server does answer (200 with
the flow JSON) but without `Access-Control-Allow-Origin`, so the page cannot read it; an
OPTIONS preflight to `/login/v2/poll` returns 405. The flow is not a DAV route, so
WebAppPassword's CORS does not cover it; stock does not either. Upstream context:
[nextcloud/server#34898](https://github.com/nextcloud/server/issues/34898) (CORS support in
login v2 and OAuth2 flow, still open).

**WebAppPassword's popup flow (T15).** WebAppPassword ships its own connect flow
(`templates/index.php`, `js/script.js`, `PageController::createToken` in v26.8.0) that
avoids CORS entirely:

1. The app, on a user click, opens `/index.php/apps/webapppassword/?target-origin=<app origin>`
   in a popup.
2. Nextcloud redirects to its normal login page (so two-factor and SSO apply), then back.
3. Same-origin inside the popup, the page POSTs to `/apps/webapppassword/create` with the
   session's request token. Nextcloud creates an app token and the page calls
   `window.opener.postMessage({type: "webapppassword", loginName, token, webdavUrl}, targetOrigin)`.
   Origins not on the allow-list get a 403 page without the script.

Results on 34/webapppassword and 35/webapppassword: the popup landed on
`/login?redirect_url=/index.php/apps/webapppassword/?target-origin=…`; after login, the
opener received the message from `http://nextcloud` with a 72-character token and
`webdavUrl` `http://nextcloud/remote.php/dav/files/rstest/`; a cross-origin PROPFIND with
`loginName:token` returned 207; the same logged-in session asking for
`target-origin=http://evil.example` got 403 and no script. T15 fails on stock and on the PR
build only because the app is not installed there (the popup shows "Page not found").

**Token lifetime.** `results/<v>-webapppassword-tokens.json` records the token's
`oc_authtoken` row: `expires` is exactly 86 400 s after issue, matching
`Application::TOKEN_LIFETIME = 86400` (a hard-coded constant); a background job removes
expired tokens. There is no refresh token, so after 24 hours the app has to open the popup
again. If the user is still logged in to Nextcloud in that browser, the popup completes
without typing, but it needs a click to get past popup blockers.

For comparison, the existing remoteStorage.js backends: Dropbox access tokens are also short-lived,
but the Dropbox backend uses OAuth2 PKCE with `token_access_type: 'offline'` and silently
refreshes on 401 (`src/dropbox.ts`, `Authorize.refreshAccessToken` in `src/authorize.ts`).
The Google Drive backend has no refresh logic and asks the user to reconnect when its token expires.
A WebAppPassword connect therefore sits between the two: no silent refresh, but a longer
interval than Google Drive's.

Connect options for Option A, in preference order:

1. **WebAppPassword popup flow** (T15): works today wherever WebAppPassword is the CORS
   provider, which Option A needs anyway. Reconnect daily via the same popup.
2. **App-password paste** as a fallback for users who want a permanent credential: the
   user creates an app password in Nextcloud settings and pastes it; the backend validates
   it with a PROPFIND. Works with any DAV CORS provider, including the PR.
3. **Upstream, for silent renewal:** Nextcloud's OAuth2 app already issues refresh tokens
   (`grant_type=refresh_token`), but it requires a client secret, has no PKCE and sends no
   CORS on its token endpoint, so a browser app cannot use it. Adding PKCE and CORS there
   would let a Nextcloud backend work exactly like the Dropbox one. CORS on login/v2
   (#34898) would remove the WebAppPassword dependency for connect. Making WebAppPassword's
   lifetime configurable would only lengthen the window, and is not recommended over these.

### R7 — Scoping: known gap, recommendation

Nextcloud app passwords are account-wide; there is no per-folder restriction. Recommendation:
**dedicated Nextcloud user** whose entire account is the remoteStorage store (with the
`remotestorage/` folder as the root), rather than a shared account with a dedicated folder.
That gives real isolation, a revocable credential, and a clean quota, without pretending the
password is scoped. A dedicated folder in a shared account is acceptable only if the user
understands the app can read the whole account.

### PR #40537: stale draft, broken as written, DAV CORS works once fixed

Checked on 2026-10-02 against branch `feat/cors-on-webdav`, head
`338f1cb5bfff8d5045014006f38be27d2687b9ae`:

- **Still a draft.** The milestone moved through 28 → … → 34.0.1 and was then removed; the
  branch was last touched Aug 2026 with codestyle commits.
- **Based on 28.0.0 dev, not current master.** `version.php` says `28.0.0.2` / `28.0.0 dev`.
  Running the branch source over a 35 image stops at the upgrade guard: *"Can't start
  Nextcloud because upgrading from 28.0.0.2 to 35.0.1.1 is not supported."*
- **Does not run as written.** `apps/dav/lib/Server.php` calls
  `\OC::$server->get(IUserSession)` — an undefined constant, since `use OCP\IUserSession;`
  is missing — and `get(IConfig::class)` without its import. Every DAV request returns 500
  with `Undefined constant "OCA\DAV\IUserSession"` until fixed.
- **A third latent bug:** `apps/dav/lib/Connector/Sabre/CorsPlugin.php` uses
  `LoggerInterface::class` without importing it. It is only reached when the Origin header
  is malformed, so it did not affect these tests.
- **With the DAV subset applied to 28.0.14.1 and the two fixes made, T11–T13 pass.** Actual
  responses to the allow-listed origin echo it in `Access-Control-Allow-Origin`, carry a
  large allowed-header list (including `Authorization`, `Depth`, `If-Match`,
  `If-None-Match`) and `Access-Control-Expose-Headers` including `ETag`; GET, PUT and DELETE
  also send `Vary: Origin` (PROPFIND does not). T14 still fails (login flow, as above).
- **Review point: the preflight ignores the allow-list.** A credential-less OPTIONS gets
  `200` with `Access-Control-Allow-Origin: *` and the full method/header lists for *any*
  origin, including `http://evil.example`. Enforcement happens only on the actual response,
  where a foreign origin gets no `Access-Control-Allow-Origin`. Browsers still block a
  foreign page from reading responses, and cookie-credentialed requests fail against a `*`
  preflight, but a foreign page can still send requests carrying an `Authorization` header it
  supplies. Checking the allow-list in the preflight too would be tighter (WebAppPassword
  does this).
- **Config keys:** `cors.allowed-domains` (array, admin) and `cors.allow-user-domains`
  (bool). On 28, `occ config:system:set cors.allowed-domains 0 --value=…` is the working
  invocation; `--type=json` is rejected by that release.

The three fixes are small and independent of the CORS design; together with the preflight
review point they are worth posting on the PR even though the branch needs a rebase before
it can land.

## Verdict on the two options

**Option A — client-side Nextcloud backend.** Feasible today on servers where DAV CORS can
be enabled: R1–R4 are solid, and with WebAppPassword the browser can run every DAV method
sync uses and read every ETag the server sends (verified on 34 and 35). Two conditions:

1. CORS must be enabled by an admin (WebAppPassword, or the PR once rebased and fixed).
   Without it the backend cannot work in a browser at all.
2. Connect cannot use Login Flow v2 from the browser (R6). On WebAppPassword servers, use
   its popup flow (T15: 24-hour tokens, reconnect via the same popup), with app-password
   paste as the fallback and the only option on the PR. Scope with a dedicated user (R7).

A backend would implement `configure`/`connect` plus `get`/`put`/`delete`; folder listings
come back from `get()` as an items map keyed by child name with `ETag` per child and the
folder's own ETag as `revision` — exactly what PROPFIND Depth 1 gives. Nothing beyond the
Dropbox/Google Drive contract is needed; their item-URL/share-link hooks are optional.

**Option B — Armadietto WebDAV store router.** Unaffected by browser CORS and able to add
discovery, OAuth scoping and its own index on top of WebDAV. It depends on the same
Nextcloud behaviours and they all pass, including the recursive ETags a proxy needs to avoid
a full crawl. It still requires someone to run a service holding users' WebDAV credentials.

**Recommendation.** Build Option A as the user-facing path for Nextcloud, connecting via
WebAppPassword's popup flow with app-password paste as the fallback, and keep Option B for
servers where CORS cannot be enabled. Raise PKCE + CORS for Nextcloud's OAuth2 app upstream
as the route to silent token renewal.
Push the two PR fixes upstream and, if the branch is rebased, offer these results on the PR.

## Open questions from the plan

| Question | Answer |
| --- | --- |
| Is PR #40537 still a draft, does it build against current Nextcloud? | Still a draft; based on 28.0.0 dev; does not run as written (missing imports, undefined constant). DAV CORS passes on 28.0.14.1 once fixed. |
| WebAppPassword's config key and ETag exposure? | App value `origins` (`occ config:app:set webapppassword origins`); `Access-Control-Expose-Headers: etag, dav`; ETag readable on PUT and GET, absent on DELETE. |
| Does folder ETag propagation lag on write? | No. Root changed on the first read after PUT in every run (171–216 ms including the request). |
| Scoping (R7) recommendation? | Dedicated Nextcloud user (account-wide app password), not a dedicated folder in a shared account. |
| Default matrix? | Latest two majors (35, 34) × stock and WebAppPassword; PR variant separately on its matching 28.x base. |
| Backend interface beyond Dropbox/Google Drive? | No. `get`/`put`/`delete` plus folder listings from `get` with ETag revisions covers it; the rest are optional hooks. |

## Reproduction

```sh
git clone https://github.com/jonocodes/remotestorage-nextcloud-harness.git
cd remotestorage-nextcloud-harness
./run.sh                                   # 35/34 × stock/webapppassword
VERSIONS=28 VARIANTS=pr40537 ./run.sh      # builds the patched PR image
./scripts/summary.sh                       # renders the matrix
```

Raw artefacts: `results/<version>-<variant>.json` (one object per case), `-curl.json` /
`-browser.json` (per stage), `-cors-headers.txt` (raw headers), `-tokens.json` (app-token lifetimes), `-nextcloud.log`, and
`results/fixtures/`, and per-run status snapshots in `results/runs/run1–6.tsv`. Session
cookie values in the header captures are redacted. See `README.md` for the runbook and stop
conditions.

---

## Appendix A — short CORS-only version (for Nextcloud threads)

> We tested remoteStorage.js speaking Nextcloud WebDAV from a browser on another origin,
> against stock Nextcloud 35.0.1 and 34.0.4 in Docker.
>
> **Without an app:** stock rejects the browser's credential-less preflight on DAV routes
> with 401 and no CORS headers, and authenticated PROPFIND/GET/PUT/DELETE responses carry no
> `Access-Control-Allow-Origin` either.
> The browser blocks with `TypeError: Failed to fetch` while the same page can read
> `/status.php`, so this is purely CORS. Everything non-browser works: recursive folder
> ETags update immediately on create/update/delete, `If-Match`/`If-None-Match` return 412,
> Depth-1 listings are complete, and a file's GET `ETag` matches the parent's `getetag`.
>
> **With WebAppPassword:** PROPFIND, GET, PUT and DELETE all work from the other origin and
> `ETag` is readable (`access-control-expose-headers: etag, dav`), including visible 412s
> for stale `If-Match`. DELETE responses carry no ETag at all (server behaviour, same on
> stock and to same-origin `curl`), so no CORS setting can expose one there.
> Origins not on the list are refused at the preflight (401).
>
> **Login Flow v2 from a browser is still blocked** on both stock and WebAppPassword:
> `POST /index.php/login/v2` is not a DAV route and gets no CORS headers. WebAppPassword's
> own popup + `postMessage` flow does work (token usable cross-origin, foreign origins get
> 403), but its tokens last 24 hours with no refresh. CORS on login/v2 and the poll
> endpoint, or PKCE + CORS on the OAuth2 app's token endpoint, would give browser-based
> clients a standard connect with renewal. (#34898, #3131)
>
> **PR #40537:** still a draft; branch based on 28.0.0 dev, so it does not run against
> current Nextcloud, and `apps/dav/lib/Server.php` has an undefined `IUserSession` constant
> plus missing `OCP` imports (and `CorsPlugin` uses `LoggerInterface` without importing it).
> With the DAV subset applied to 28.0.14.1 and those fixed, actual responses give a browser
> client what it needs (origin echo, `ETag` exposed, full allowed-header list). One review
> point: the preflight answers `Access-Control-Allow-Origin: *` for any origin and only the
> actual response checks the allow-list.

## Appendix B — evidence index

| Artefact | Contents |
| --- | --- |
| `results/<v>-<variant>.json` | Merged per-case results: id, variant, version, status, expected, observed, evidence |
| `results/<v>-<variant>-cors-headers.txt` | Raw response headers with `Origin` set: credential-less preflight, PROPFIND/GET/PUT/DELETE, a non-allow-listed origin, and login/v2 |
| `results/<v>-<variant>-nextcloud.log` | Container log for the run (version, install, access log) |
| `results/fixtures/<v>-<variant>/` | T10 PROPFIND XML and its JSON mapping |
| `results/<v>-<variant>-browser.json` | Browser cases including control and per-request statuses/ETags |
| `results/<v>-<variant>-tokens.json` | Every app token Nextcloud holds after the browser cases, with `expires` and `lifetime_seconds` (T15's WebAppPassword token: 86400) |
