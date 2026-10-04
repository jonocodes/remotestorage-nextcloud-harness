# remoteStorage on Nextcloud via a thin app: Plan

Oct 2, 2026 · @Jono

> Second track, run in parallel with [`PLAN.md`](PLAN.md) and reported separately (`REPORT-app.md`,
> not written yet). `PLAN.md` asks what stock Nextcloud and WebAppPassword can do for a
> remoteStorage.js backend that speaks WebDAV. This plan asks whether a small Nextcloud app can
> turn Nextcloud into a real remoteStorage server, so that **any existing remoteStorage app
> works unchanged**, with no core patches.

## Summary

Goal: an instruction an admin can follow — "install app *X* (version *Y*) on Nextcloud 34 or
35" — after which a user types `user@their-nextcloud` into any remoteStorage app and it syncs.

Design principle: **fill only the gaps; leave every file operation to Nextcloud's own WebDAV.**
The app is a WebFinger handler, an OAuth consent page with scoped tokens, a login plugin and a
WebDAV plugin, all attached through Nextcloud's public extension points. Everything `PLAN.md`
R1–R4 verified (ETags, their propagation, `If-Match`/412, locking, quotas, versions, trash, the
Files UI) is reused, not rebuilt.

History supports this shape (see `PLAN.md`): Nextcloud closed the request for remoteStorage
support ([#843](https://github.com/nextcloud/server/issues/843), 2016) with "should be done as
separate apps", and ownCloud's built-in support was removed after it broke from lack of
maintenance ([owncloud/core#12686](https://github.com/owncloud/core/issues/12686)). The lesson
is the maintenance risk: keep the app small, depend only on public extension points, and run
this harness against each new Nextcloud major so breakage is caught before users hit it.

## Why a new app, not WebAppPassword or a fork

| Part | In WebAppPassword? |
| --- | --- |
| CORS on WebDAV | Yes, but with an admin origin allow-list. remoteStorage needs any app to work, with trust coming from the user's OAuth consent. |
| WebFinger, OAuth consent, scoped tokens | No. WebAppPassword issues core app passwords, which are account-wide. |
| Folder JSON listings, PUT creating parent folders, DELETE pruning empty ones | No; remoteStorage-specific. |

A fork would save only the ~60-line CORS plugin. The app copies that approach with credit
(WebAppPassword is AGPL-3.0; this app will be too) and must coexist with WebAppPassword installed.

## Where the gap is

What a remoteStorage client does, and who handles it:

| Client step | Handled by |
| --- | --- |
| `GET /.well-known/webfinger?resource=acct:user@host` | **App** — `OCP\Http\WellKnown\IHandler` (NC 21+). Nextcloud's shipped `.htaccess`/nginx config already route this path to Nextcloud. |
| Open the OAuth dialog, receive a token for `notes:rw` | **App** — consent page plus its own token table. |
| Requests with `Authorization: Bearer <token>` | **App** — auth backend via `OCA\DAV\Events\SabrePluginAuthInitEvent` (NC 20+); enforces scope by path. |
| CORS preflight and headers, exposing `ETag` | **App** — WebDAV plugin via `OCA\DAV\Events\SabrePluginAddEvent` (NC 28+). |
| GET on a folder → `folder-description` JSON | **App** — WebDAV plugin, built from the folder's children (same mapping as `PLAN.md` T10). |
| PUT to a path whose parents don't exist | **App** creates the parents, then **WebDAV** does the PUT. |
| DELETE leaving empty parent folders | **WebDAV** deletes, then the **App** prunes empty parents. |
| GET/PUT/DELETE on documents, `If-Match`, `If-None-Match`, ETags, 412 | **WebDAV**, unchanged. |
| Unauthenticated GET of documents under `/public/` | **App** — open question; see AR8. |

Storage root: a folder in the user's files (default `remoteStorage/`), served at
`/remote.php/dav/files/<uid>/remoteStorage/`. The WebFinger record's `href` points there.

**Inert by default.** The WebDAV plugin acts only on requests authenticated with one of the app's
tokens. Desktop/mobile clients, the web UI and WebAppPassword see Nextcloud exactly as before.

## Requirements

| ID | Requirement | Why |
| --- | --- | --- |
| AR1 | WebFinger answers `acct:<login>@<host>` with a `remotestorage` link: `href` = storage root, `properties` with `http://remotestorage.io/spec/version` and the OAuth URL under `http://tools.ietf.org/html/rfc6749#section-4.2`. Unknown users get 404. | remoteStorage.js discovery (`src/discover.ts`) |
| AR2 | OAuth implicit grant: the consent page requires a Nextcloud login, shows the requesting origin and scopes, and redirects to `redirect_uri` with `#access_token=…`. Denial redirects with `error=access_denied`. `redirect_uri` must share the origin of `client_id`. | rs OAuth flow |
| AR3 | Tokens are the app's own, stored hashed, tied to user, client origin and scopes. They are listed and revocable in the user's personal settings. No expiry by default. | Revocable, long-lived, unlike WebAppPassword's 24 h (`REPORT.md` R6) |
| AR4 | Scope enforcement: `notes:r` allows GET/HEAD under `/notes/`; `:rw` adds PUT/DELETE; `*:rw` covers the root. Out-of-scope requests get 403. | Fixes `PLAN.md` R7 |
| AR5 | CORS for token-authenticated requests from any origin: preflight succeeds without credentials, `Access-Control-Expose-Headers` includes `ETag`, `Content-Type`, `Content-Length`, and no cookies are honoured on those requests. | Browser apps on any origin |
| AR6 | Folder GET returns `{"@context":"http://remotestorage.io/spec/folder-description","items":{…}}`: subfolders with `ETag`; documents with `ETag`, `Content-Type`, `Content-Length`, `Last-Modified`. The folder's ETag is in the response `ETag` header and equals its WebDAV `getetag`. Empty and missing folders behave as the spec requires. | rs listing format (`src/wireclient.ts`) |
| AR7 | Document semantics match the spec: PUT creates missing parents; DELETE prunes empty parents; `If-Match`/`If-None-Match` give 412 (or 304 on GET) as specified; every ETag equals the WebDAV `getetag` of the same node. | Conflict detection and sync |
| AR8 | `/public/` documents readable without a token; `/public/` listings are not. | rs spec public folder |
| AR9 | Non-interference: without an app token, every response from `/remote.php/dav` is byte-for-byte the same as with the app disabled. Works alongside WebAppPassword without duplicate CORS headers. | Safe to install on an existing server |
| AR10 | Supported versions: the latest two Nextcloud majors (34, 35 today); no core files modified. | The admin instruction |

## Spike first

Four unknowns could change the design. Answer them before building the full app; each is a
throwaway probe against the harness stack.

| Spike | Question | If it fails |
| --- | --- | --- |
| S1 | Does a backend added via `SabrePluginAuthInitEvent` receive `Authorization: Bearer` requests, given that core has its own `BearerAuth` and brute-force throttling of failed token logins? | Use a distinct auth scheme or a query-free header, or serve storage from an app route that calls WebDAV's tree in-process. |
| S2 | Can a WebDAV plugin intercept GET on a collection before core's handlers (e.g. at high priority on `method:GET`) and return JSON? | Same fallback as S1. |
| S3 | Does the WebDAV `getetag` equal what the plugin can read from the node for both files and folders, quoted identically? | Normalise in the plugin; record the rule. |
| S4 | Does unauthenticated access to `/public/` documents work through the auth plugin without opening anything else? | Serve `/public/` from an app route; or descope AR8 for v1. |

Plus one client check: does remoteStorage.js's WebFinger lookup work over plain `http://` inside
the harness, or does the harness need TLS on the Nextcloud container?

### Spike results (2026-10-02)

**All four spikes and the client check pass on Nextcloud 35.0.1 and 34.0.4; the design holds.**
The throwaway app is `spike/rsspike/` (about 430 lines of PHP, comments included); `spike/run.sh` builds a fresh
stack per version and runs `spike/probe.sh` (28 HTTP checks) plus `runner/spike.spec.ts`
(2 remoteStorage.js checks). Two consecutive runs: 60/60 pass, identical. Evidence in
`results/spike/`.

| Spike | Answer |
| --- | --- |
| S1 | **Yes.** A backend added via `SabrePluginAuthInitEvent` runs *before* core's `BearerAuth` and Basic/cookie backends (`apps/dav/lib/Server.php`). On a valid token it calls `IUserSession::setVolatileActiveUser()` and `OC_Util::setupFS()`: a login for this request only, nothing written to the session. Unknown tokens fall through to core and get 401; scope, root and method limits give 403/405; Basic-auth requests are unchanged. |
| S2 | **Yes.** A `method:GET` listener at priority 50 runs before Sabre's own GET (100) and returns the `folder-description` JSON for collections. Without a token, core's HTML "This is the WebDAV interface" page is unchanged. |
| S3 | **Yes.** Document `ETag` header = PROPFIND `getetag` (quoted); listing item `ETag` = `getetag` without quotes; folder `ETag` header = the folder's `getetag`. |
| S4 | **Yes, after a fix.** Anonymous GET/HEAD of documents under `public/` is let through as a read-only, public-only login; listings, writes and private paths get 401. |
| Client | **Yes over plain HTTP** (`src/discover.ts` sets `tls_only: false`). Unmodified remoteStorage.js 2.0.0-beta.9 (`origin/vendor/`) connects as `rstest@nextcloud` via WebFinger, then stores, reads and lists directly (SC1), and with caching on syncs a file that a fresh browser context syncs back down (SC2). |

Findings that change the real app's design:

- **Folder-vs-document must come from the raw URL.** Sabre's `getPath()` strips the trailing
  slash, and in remoteStorage that slash is what makes a path a folder. The first spike
  version leaked the `public/` listing to anonymous requests because of this. Fixed with
  defence in depth (raw-URL check in auth, refusal in the folder handler, and a 404 for a folder
  addressed without its slash); S4b/S4c are the regression checks.
- **Core does not throttle failed bearer tokens.** Ten wrong tokens in a row caused no delay.
  Good for S1, but the app's tokens get no brute-force protection from core: use ≥256-bit
  random tokens and the app's own throttling (`OCP\Security\Bruteforce\IThrottler`).
- **CORS only for bearer-token and anonymous requests.** Preflights can't carry credentials,
  so they are answered for any origin under the storage root; actual responses get
  `Access-Control-Allow-Origin: *` only when the request used a bearer token or none (so a
  bad token's 401 is readable). Basic-auth requests keep core's behaviour exactly (C5). This
  replaces AR9's "only with an app token" wording for preflights.
- **Core sets session cookies on every DAV response,** including Basic-auth requests and
  anonymous 401s; not caused by the app. Harmless cross-origin: with `*`, browsers neither
  send nor store credentials.
- **WebFinger reaches Nextcloud** through the shipped `.htaccess` rewrite (without a handler,
  core answers `{"message":"webfinger not supported"}`). Handlers must merge into a previous
  `JrdResponse` (Circles also registers one) and add `Access-Control-Allow-Origin: *` via a
  wrapping response, since `JrdResponse` sets no CORS.

Not covered by the spike (to build next): the OAuth page and token table (the spike has one
token in app config), PUT creating parents (the checks pre-create folders), DELETE pruning,
`If-None-Match` 304 on folders, and AT10/AT11.

## Test cases

All run in this harness as a new variant `rsapp` (the app mounted into `custom_apps/`), plus
`rsapp+webapppassword` for AR9. Storage root `$S` = `/remote.php/dav/files/rstest/remoteStorage/`.

| Case | Req | Runs in | Steps | Pass when |
| --- | --- | --- | --- | --- |
| AT1 | AR1 | curl | WebFinger for `acct:rstest@nextcloud` and for an unknown user. | Correct link and properties; unknown → 404. |
| AT2 | AR2, AR3 | browser | Start OAuth from the origin page for `notes:rw`; log in; approve. Repeat and deny. | Token in the redirect fragment; denial gives `access_denied`; token listed in settings. |
| AT3 | AR4 | curl | With a `notes:r` token: GET under `/notes/` (ok), PUT under `/notes/` (403), GET under `/other/` (403). | As stated. |
| AT4 | AR5 | browser | From the origin page: PROPFIND-free GET of a folder, PUT, GET, DELETE with the token. | All succeed; `ETag` readable on each. |
| AT5 | AR6 | curl | Build a small tree; GET each folder. | Listing matches the JSON schema; every `ETag` equals the WebDAV `getetag` of the same node. |
| AT6 | AR7 | curl | PUT `/notes/a/b/c.txt` into an empty root; DELETE it. | Parents created, then pruned. |
| AT7 | AR7 | curl | Stale `If-Match` PUT and DELETE; `If-None-Match: *` on an existing file; `If-None-Match` GET with the current ETag. | 412, 412, 412, 304; nothing written. |
| AT8 | AR6, AR7 | curl | Re-run `PLAN.md` T1–T3 through the rs interface (folder GETs instead of PROPFIND). | Folder ETags change all the way up to the root, immediately. |
| AT9 | AR8 | curl | Unauthenticated GET of `/public/x.txt` and of `/public/`. | Document 200; listing 401/403. |
| AT10 | AR9 | curl | Capture full responses for a fixed set of Basic-auth WebDAV requests with the app enabled and disabled; diff. On `rsapp+webapppassword`, check CORS headers appear once. | No diff; no duplicate headers. |
| AT11 | all | external | Run the community server test suite [`remotestorage/api-test-suite`](https://github.com/remotestorage/api-test-suite) against the storage root with a `*:rw` token. | All required tests pass. |
| AT12 | all | browser | Load remoteStorage.js (release build) in the probe page, connect as `rstest@nextcloud` through discovery and OAuth, store, sync, then read the same object back from a second browser context. | Round-trip succeeds; the file is visible via WebDAV and in the Files UI. |

AT11 and AT12 are the headline: one is the ecosystem's own conformance suite, the other is an
unmodified remoteStorage.js app.

### Build results (2026-10-02)

The app is [jonocodes/nextcloud-remotestorage](https://github.com/jonocodes/nextcloud-remotestorage)
0.1.0: 72 unit tests for its pure logic (`just test`), and the integration cases in this
harness's `app/` (`app/run.sh`, `app/probe.sh`, `app/snapshot.sh`, `runner/app.spec.ts`).
**All cases implemented so far pass on Nextcloud 35.0.1 and 34.0.4, with the app alone and
next to WebAppPassword: 240/240 per run, identical over three consecutive runs; the committed
evidence is from run 3, against app commit `ee61360`.** Evidence in
`results/app/`; the app commit under test is in `results/app/*-app-version.txt`.

| Case | Status | Notes |
| --- | --- | --- |
| AT1 | pass | WebFinger link, properties, CORS; unknown user and foreign host → 404. |
| AT2 | pass | Real consent flow in Chromium: Allow → `#access_token=rs_…&token_type=bearer&scope&state`; Deny → `access_denied`; a `client_id` that is not the redirect origin → error page, no redirect; the token is listed in Settings → Security and **Disconnect** makes it 401. |
| AT3 | pass | `notes:r`/`notes:rw`/`*:rw`, `/public/notes/` covered by `notes`, root needs `*`, nothing outside the root, non-remoteStorage methods → 405. |
| AT4 | pass | From a page on another origin: PUT, GET, folder GET, stale `If-Match` 412 and DELETE, with every ETag readable. |
| AT5 | pass | Listing format and metadata; every ETag equals WebDAV's `getetag`. |
| AT6 | pass | PUT into a user with no storage root creates every parent; DELETE prunes emptied parents up to (not including) the root; PUT below a document → 409; PUT/DELETE on a folder → 405. |
| AT7 | pass | 412 for stale `If-Match` (PUT, DELETE) and `If-None-Match: *`; 304 for documents and folders; an `If-Match` PUT to a missing path creates no folders. |
| AT8 | pass | Root, module and parent folder ETags all change on create and on delete. |
| AT9 | pass | Anonymous: public documents 200; public listings, writes and private documents 401. |
| AT10 | pass | Basic-auth WebDAV responses (10 requests, volatile headers dropped) identical with the app disabled and enabled. |
| AT11 | not run | Community `api-test-suite` (Ruby) not wired in yet (done in the second round below). |
| AT12 | pass | Unmodified remoteStorage.js 2.0.0-beta.9: `connect("rstest@nextcloud")` → WebFinger → Nextcloud login → consent → back with the token → sync a file into `notes/deep/a/` → visible via WebDAV → `remove()` + sync → the emptied folders are gone. |
| C1–C6, A1–A3, W1–W2 | pass | CORS rules, request-only logins (a token request's cookies log nobody in), non-`rs_` bearer tokens untouched and unthrottled, bad `rs_` tokens throttled; with WebAppPassword exactly one `Access-Control-Allow-Origin`. |

Changes from the plan, each recorded here rather than silently made:

- **AT10 covers Basic-auth requests only.** Answering credential-less browser preflights under
  the storage root is the one intended change (see the spike's CORS finding), so preflights are
  not in the snapshot.
- **Tokens are prefixed `rs_`.** The auth backend ignores, and never throttles, any other bearer
  token, so core OAuth2 and SSO apps are unaffected (A2).
- **Throttling sleeps on failure only.** In Nextcloud 34 and 35 `IThrottler::sleepDelayOrThrowOnMax()`
  no longer sleeps (it blocks after the limit and returns the delay); the app sleeps itself
  after a failed token, like core's `BruteForceMiddleware`.
- **Not in the plan:** `occ remotestorage:token:issue` (for scripts and the curl checks), and
  deleting a user's tokens with the user.

Found by the harness while building (all fixed):

- Route `oauth#authorize` resolves to class `OauthController`, not `OAuthController`; the
  consent page returned an error until renamed.
- Nextcloud generates the pretty OAuth URL (`/apps/remotestorage/oauth`, no `index.php`); both work.
- The consent form needs the app's origin in CSP `form-action`, since Chrome applies it to the
  redirect after the form post; with it, the redirect back works (AT2a, AT12).
- **First-run wizard:** a brand-new user's first login shows Nextcloud's first-run wizard on top
  of the consent page; the harness clicks Skip and Close, as a person would. A UX issue to
  consider in the app, not a failure.

Still open at this point: AT11; nginx deployments; OAuth code flow with PKCE; app-store signing.

### Second round (2026-10-03): nginx, AT11, spec corrections — app 0.2.0

**Result: all cases pass on Nextcloud 34 and 35 behind Apache (67/67), Apache next to
WebAppPassword (69/69) and nginx with two config additions (67/67); with nginx's official config
unchanged, only discovery-related cases fail (63/67), as expected.** Three consecutive runs gave
identical statuses apart from that config change; the committed evidence is from the third, against
app commit `be660b2`. Evidence in `results/app/`; the community
suite's raw output in `results/app/*-api-test-suite.txt`.

**nginx.** New variants run php-fpm behind nginx in the nextcloud container's network namespace
(`compose.nginx.yaml`), with Nextcloud's official config verbatim (`docker/nginx/nginx.conf`) or
with one added `location` (`nginx-webfinger-rewrite.conf`). The official config answers
`/.well-known/webfinger` with a 301. Adding `Access-Control-Allow-Origin` to that redirect does
not help: remoteStorage.js's WebFinger library (webfinger.js 3) fetches with
`redirect: "manual"`, which a browser turns into an opaque response, so it can follow no
redirect at all. An internal `rewrite` fixes it. New checks: AT1e (every WebFinger response in
the chain carries CORS) and AT1f (no redirect).
nginx also gzips JSON (including folder listings) and turns compressed responses' ETags weak,
which the suite flags; the fixed config turns gzip off for requests with an `rs_` token
(`if ($http_authorization ~ "^Bearer rs_") { gzip off; }` in the PHP location), checked by the
full matrix including the browser cases.
**AT11** runs the community suite (`docker/api-test-suite`, pinned to `55cc9a2`, Ruby 2.7) as its
own empty user `rssuite`, with `rsother` as the second account. The first run against app 0.1.0
passed 42 of 53. AT11 passes when every failing suite test is listed, with its reason, in
`docker/api-test-suite/known-false-positives.txt`; that file has one entry (anonymous 401s
differ only by Nextcloud's per-request session cookies). This is a recorded exception, not a
loosened criterion: any other failure fails AT11.

**Spec corrections in the app (0.2.0)**, each found by AT11 or the new checks:

- Content-Type is stored per file id and ETag and returned on GET/HEAD and in listings (AT5h).
- Same-size overwrites within one second got the same ETag from Nextcloud's local storage
  (`md5(mtime seconds, inode, device, size)`); the app now forces a fresh ETag and propagates it
  (AT7k).
- Compressed responses changed the ETag clients send back (`-gzip` on Apache, `W/` on nginx),
  causing false 412s; the app normalises conditional headers and disables compression on
  Apache + mod_php (AT7i; AT12's second device edits after a compressed read).
- Overwrites and deletes answer 200, not 204; preflights are answered even when they carry a
  token, echoing the origin (never with credentials).
- Missing and empty folders list as empty (AT6i), and empty subfolders are not listed. Files_Trashbin's
  `afterMethod:GET` hook threw `NotFound` for missing folders; the app sends that response
  itself.

AT12 now uses two devices: device B connects separately, syncs, reads (compressed), edits and
deletes; no conflicts.

Changes to checks: DELETE and overwrite expectations moved from 204 to 200, CORS from `*` to the
echoed origin, and "pruned"/"missing folder" checks to WebDAV PROPFIND, all because the app's
behaviour changed to match the spec.

Still open: PKCE (deferred, see open questions), the first-run wizard, app-store signing,
databases other than SQLite.

## Repositories

- **The app:** its own repository (needed for app-store releases), app id `remotestorage`.
  Tests for the PHP code live there.
- **This harness:** adds the `rsapp` and `rsapp+webapppassword` variants, AT1–AT12, and
  `REPORT-app.md`. It pins the app version under test so results stay reproducible.

## LLM runbook

1. Run spikes S1–S4 and the WebFinger-over-HTTP check; record each answer in this file, dated.
   **Stop and ask** if any spike fails, since the fallback changes the design.
2. Scaffold the app; add the `rsapp` variant; implement AR1 → AR9 in order, adding each AT case
   before its implementation (test first).
3. Run the matrix (34, 35 × `rsapp`, `rsapp+webapppassword`) twice; triage as in `PLAN.md`.
4. Write `REPORT-app.md`: matrix, AT11 and AT12 results, the admin instruction, open issues.

**Stop and ask a human when:** a spike fails; a requirement needs a core change; anything would
be published, pushed or posted; or a pass needs a looser criterion.

## Open questions

- [x] Do the spikes pass (S1–S4)? — Yes, on 34 and 35, plus the remoteStorage.js client check; see "Spike results".
- [x] OAuth code flow with PKCE as well as implicit grant? — Deferred (2026-10-03): remoteStorage.js
      2.0.0-beta.9 uses PKCE only for Dropbox (built-in token URL); for remoteStorage servers it always
      sends `response_type=token`, and the spec defines no token-endpoint discovery.
- [x] Storage root name and whether users may change it. — `remoteStorage` by default; admins can change it (`occ config:app:set remotestorage storage_root`); not per user.
- [ ] App-store listing and signing: who holds the certificate?
- [ ] Prior art: read what is recoverable of ownCloud's removed remoteStorage app for pitfalls
      before building.

## Sources

- remoteStorage protocol: <https://datatracker.ietf.org/doc/draft-dejong-remotestorage/>
- remoteStorage.js discovery: `src/discover.ts`; listing parsing: `src/wireclient.ts`
- Nextcloud well-known handlers: `lib/public/Http/WellKnown/IHandler.php` (since 21)
- Nextcloud DAV events: `apps/dav/lib/Events/SabrePluginAuthInitEvent.php` (20),
  `SabrePluginAddEvent.php` (28); dispatched from `apps/dav/lib/Server.php`
- WebAppPassword CORS plugin: <https://github.com/digital-blueprint/webapppassword> (AGPL-3.0)
- Server conformance suite: <https://github.com/remotestorage/api-test-suite>
