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

- [ ] Do the spikes pass (S1–S4)?
- [ ] OAuth code flow with PKCE as well as implicit grant? (remoteStorage.js 2.0 can do PKCE for
      Dropbox; check what its rs discovery path accepts.)
- [ ] Storage root name and whether users may change it.
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
