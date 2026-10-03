# remoteStorage.js × Nextcloud: History and Test Plan

Sep 30, 2026 · @Jono

> This is the spec the harness in this repository implements, kept here as the canonical
> version. Changes made after the runs are dated inline (see T12). Results are in
> [`REPORT.md`](REPORT.md). The harness differs from the design below in one way: the
> automated browser uses the origins `http://origin` / `http://nextcloud` instead of
> `*.localhost`, explained in [`README.md`](README.md).

## Summary

remoteStorage.js has no Nextcloud backend because generic WebDAV fails four requirements: discovery, CORS, scoped permissions and consistent behavior. Nextcloud specifically may pass three of them, and that has never been tested.

The goal is an automated, LLM-runnable test that answers one question: can remoteStorage.js sync against stock Nextcloud WebDAV, and if not, exactly what is missing? The answer decides between a client-side backend in remoteStorage.js and a server-side WebDAV store router in Armadietto.

Nobody is blocked on this, but the result answers open threads on both projects: remotestorage.js #1320, a never-answered forum question from a maintainer, and Nextcloud's seven-year-old CORS issue #3131.

## History: remoteStorage

The remoteStorage protocol began on WebDAV and abandoned it; maintainers have rejected a generic WebDAV backend repeatedly but always said a contributed one would be accepted.

| Date | Thread | What it established |
| --- | --- | --- |
| 2025-04 → 07 | [remotestorage.js #1320](https://github.com/remotestorage/remotestorage.js/issues/1320) — "Support for more backends" (open, opened by Jono) | raucao pointed back to the #1093 reasons; said S3 has the same drawbacks plus harder credentials. rosano invited collaboration on file-based backends. Jono stated a preference for WebDAV first. |
| 2025-04 | [#1093](https://github.com/remotestorage/remotestorage.js/issues/1093) revival | coderofsalvation: "webdav is where my users/files are." Doug Reeder: a new backend is straightforward but not quick. raucao: discovery and config could be solved for ownCloud/Nextcloud specifically, as a dedicated connect option using WebDAV underneath. |
| 2022-10 → 2023-01 | [#1093](https://github.com/remotestorage/remotestorage.js/issues/1093) revival | stokito: modern servers handle CORS; manual URLs are fine; limit support to Lighttpd, Apache mod\_dav, IIS. raucao: apps would still need to adopt the adapter and its edge cases. Doug Reeder: test against as many servers as possible. |
| 2022-10 | [Forum: Issues with using WebDAV as a back-end?](https://community.remotestorage.io/t/issues-with-using-webdav-as-a-back-end/797) | Doug Reeder asked whether a lowest common denominator of WebDAV features exists. No replies. |
| 2017-11 | [#1093](https://github.com/remotestorage/remotestorage.js/issues/1093) — "Storage back-end suggestion: WebDAV" (closed) | raucao's canonical four reasons (below). Closed with PRs welcome. |
| 2015-12 | [spec #137](https://github.com/remotestorage/spec/issues/137) — MOVE verb | remoteStorage has no MOVE/COPY; WebDAV does. Debate left open. |
| 2015-12 | [spec #136](https://github.com/remotestorage/spec/issues/136) — comparison with WebDAV | Michiel de Jong: JSON listings over PROPFIND XML; WebDAV servers implement LOCK/PROPPATCH inconsistently; the spec's real additions are OAuth, CORS, WebFinger and nested folder ETags. |

**The four reasons from #1093 (2017):**

1. **Discovery.** No standard way to find a WebDAV storage; users configure by hand and get it wrong.
2. **CORS.** WebDAV servers don't send CORS headers by default, and browsers hide why a CORS request failed.
3. **Permissions.** No equivalent of OAuth scopes limiting an app to part of the storage.
4. **Complexity and fragmentation.** Implementations vary widely, and WebDAV is harder to implement server-side than remoteStorage.

The requirement that matters most for sync is not on that list: a folder's ETag must change when anything beneath it changes. remoteStorage.js relies on it to skip unchanged subtrees.

## History: ownCloud and Nextcloud

ownCloud once shipped remoteStorage server support and dropped it; Nextcloud declined to add it to core. This plan avoids both by making remoteStorage.js speak Nextcloud WebDAV, so the only server-side change needed is CORS.

| Date | Thread | What it established |
| --- | --- | --- |
| 2023-09 → 2026-08 | [nextcloud/server PR #40537](https://github.com/nextcloud/server/pull/40537) — "Allow to configure allowed domains for CORS on DAV" | Adds CORS to DAV routes, off by default, with an admin allow-list and optional per-user lists. Claims to resolve #3131. Also fixes CORS headers appearing only on OPTIONS, not the following methods. Appears to still be a draft. |
| 2023 | [nextcloud/server #37716](https://github.com/nextcloud/server/issues/37716) — CORS origin allowed list | Points to the [WebAppPassword](https://apps.nextcloud.com/apps/webapppassword) app as the current workaround; it covers WebDAV and the share API. |
| 2017-01 → now | [nextcloud/server #3131](https://github.com/nextcloud/server/issues/3131) — "Support for cross-domain WebDAV access (CORS)" (open) | About 119 comments and 63 reactions. Opening request is this use case: web apps storing user data in Nextcloud over WebDAV. |
| 2016-08 | [nextcloud/server #843](https://github.com/nextcloud/server/issues/843) — remotestorage.io support | Request for Nextcloud to act as a remoteStorage server. Closed: "should be done as separate apps." |
| 2014-12 | [owncloud/core #12686](https://github.com/owncloud/core/issues/12686) — Add support for remoteStorage | Karlitschek: supported in the past, broke from lack of maintenance, removed. Borchardt: "a bit too complicated." raucao: infeasible only as an add-on. |

One user on the [Nextcloud forum](https://help.nextcloud.com/t/accessing-files-with-a-js-webapp-hosted-on-another-domain-by-webdav-or-any-other-mean-is-it-possible/181932) reported WebAppPassword passing the OPTIONS preflight while GET and POST stayed blocked. That matches the bug PR #40537 describes and must be tested, not assumed.

## Architecture options

There are two ways to put remoteStorage.js in front of Nextcloud; the CORS test result picks between them.

| Option | How it works | Solves | Costs | Chosen if |
| --- | --- | --- | --- | --- |
| A. Client-side Nextcloud backend | A new backend in remoteStorage.js beside the Dropbox and Google Drive ones. Talks WebDAV straight to Nextcloud from the browser; connects with Login Flow v2 to get an app password. | Discovery (Nextcloud URL plus Login Flow), folder ETags (if Nextcloud propagates them) | Needs CORS on the user's Nextcloud. App password grants the whole account, not one folder. | CORS works via WebAppPassword or PR #40537. |
| B. Armadietto WebDAV store router | A server-side proxy. Armadietto's [modular server](https://github.com/remotestorage/armadietto/) already speaks the current spec and stores to S3; a new store router implements `get`/`put`/`delete` against WebDAV. | CORS, discovery (WebFinger) and scoping (OAuth) all handled by the proxy | Someone runs a service that holds users' WebDAV credentials. On servers without recursive ETags, the proxy must keep its own index and be the only writer. | CORS on Nextcloud can't be enabled by ordinary users. |

S3 is already covered: Armadietto's modular server stores to S3-compatible storage today. Its docs note it must make extra requests and create extra entries in S3, which is presumably the folder metadata bookkeeping.

Both options depend on the same Nextcloud behaviors, so one test suite serves both. Only the CORS cases are specific to option A.

## Requirements to verify

Seven behaviors decide feasibility; the first four are expected to pass on stock Nextcloud, CORS is expected to fail without an app, and scoping is a known gap.

| ID | Requirement | Why remoteStorage.js needs it | Expected on Nextcloud |
| --- | --- | --- | --- |
| R1 | Recursive folder ETags: a folder's ETag changes on any create, update or delete beneath it, immediately | Sync skips subtrees whose folder ETag is unchanged | Pass. The desktop client relies on this. Propagation delay unknown. |
| R2 | ETag consistency: a file's GET `ETag` equals its `getetag` in the parent's PROPFIND | Library compares listing ETags with document ETags | Likely pass. Check quoting and weak ETags. |
| R3 | Conditional writes: `If-Match` and `If-None-Match: *` on PUT, `If-Match` on DELETE return 412 when they don't match | Conflict detection | Likely pass (SabreDAV). |
| R4 | Listing mapping: `PROPFIND Depth: 1` yields ETag, content type, length and last-modified per child, and an ETag per subfolder | Building the JSON folder description | Pass. |
| R5 | CORS: a browser on another origin can run PROPFIND, GET, PUT and DELETE with an `Authorization` header and read the `ETag` response header | Option A only | Fail on stock; test with WebAppPassword and PR #40537. |
| R6 | Connect from the browser: obtain a working credential without the user pasting a password — via Login Flow v2, or (added 2026-10-02) WebAppPassword's popup flow | Option A's connect step | Unknown. The polling endpoint also needs CORS. |
| R7 | Scoping: restrict an app password to one folder | Matches remoteStorage's per-module OAuth scopes | Known gap. Record the mitigation chosen, not a test. |

R5 must check the `Access-Control-Expose-Headers` header specifically. Without it the browser hides `ETag`, and sync silently breaks even when requests succeed.

## Test harness design

One `docker compose` stack runs everything; deterministic scripts decide pass or fail, and the LLM orchestrates, triages and writes the report rather than judging results by eye.

| Service | Image | Role |
| --- | --- | --- |
| `nextcloud` | `nextcloud:<version>-apache`, SQLite | System under test, at `http://nc.localhost:8080`. Version is a build arg so the suite runs across a matrix. |
| `origin` | `caddy` or `nginx` serving `probe.html` | A different origin, `http://app.localhost:8081`, so the browser enforces CORS. A different port is enough. |
| `runner` | `mcr.microsoft.com/playwright` | Headless Chromium loads `probe.html`, runs the browser cases, writes `results/*.json`. |
| `curl-probe` | Small Alpine or the runner image | Runs the server-side cases (R1–R4) with curl, no browser. |

**Nextcloud variants.** Each variant is the same stack with a different setup script, run after the container reports installed:

1. `stock` — no extra apps.
2. `webapppassword` — `occ app:install webapppassword`, then allow `http://app.localhost:8081` as an origin. The exact config key needs checking against the app's README.
3. `pr40537` — a Nextcloud image built from the PR branch, with the origin added to the allow-list. Stretch goal: building server from source is heavier than pulling an image.

Setup uses `occ` through `docker compose exec -u www-data nextcloud php occ …`: create the user `rstest`, create the `remotestorage/` folder, install apps, set config. Plugins come from the Nextcloud app store by name, so adding a variant is one script.

**Where the LLM fits.** Pass/fail must come from scripts so results are reproducible and comparable across versions. The agent's jobs are:

- Bring the stack up, run each variant, and read `results/*.json`.
- On a failure, inspect logs and raw headers, and decide whether it is a harness bug or a real finding.
- Drive anything without a stable API, mainly the Login Flow v2 approval page. Playwright scripts it first; an LLM browser agent is the fallback when the UI changes.
- Write the report in the format of the Reporting section.

Any agent with a shell works: Claude Code or OpenCode for orchestration, Playwright MCP for browser control. DeepSeek or another model can drive the same Playwright MCP tools, which makes it easy to compare agents on the same runbook.

**Result format.** One JSON object per case: `id`, `variant`, `nextcloud_version`, `status` (`pass` / `fail` / `error`), `expected`, `observed`, and `evidence` (raw request and response headers, trimmed bodies). `error` means the harness broke, not Nextcloud.

## Test cases

Fifteen cases cover R1–R6 (T15 added 2026-10-02); all paths are under `/remote.php/dav/files/rstest/remotestorage/` (written `$R`), and every case starts from an empty `$R`.

| Case | Req | Runs in | Steps | Pass when |
| --- | --- | --- | --- | --- |
| T1 | R1 | curl | Record ETags of `$R`, `$R/a/`, `$R/a/b/`. PUT `$R/a/b/c.txt`. Re-read all three. | All three ETags changed. |
| T2 | R1 | curl | As T1, but overwrite `c.txt` with new content. | All three changed. |
| T3 | R1 | curl | As T1, but DELETE `c.txt`. | All three changed. |
| T4 | R1 | curl | PUT, then PROPFIND the root in a tight loop for 5 s. | Root ETag changes on the first read after PUT returns. Record latency if not. |
| T5 | R1 | curl | PUT to `$R/x/`, record `$R/y/` ETag before and after. | Sibling `$R/y/` unchanged. |
| T6 | R2 | curl | PUT a file. GET it; PROPFIND its parent. | GET `ETag` equals listing `getetag`, after normalizing quotes. Record weak `W/` ETags if seen. |
| T7 | R3 | curl | PUT with `If-Match: "stale"`. | 412, file unchanged. |
| T8 | R3 | curl | PUT with `If-None-Match: *` on an existing file. | 412, file unchanged. |
| T9 | R3 | curl | DELETE with `If-Match: "stale"`. | 412, file still exists. |
| T10 | R4 | curl | PROPFIND `Depth: 1` on a folder with two files and one subfolder. | Each file has ETag, content type, length and last-modified; the subfolder has an ETag. Save the XML-to-JSON mapping as a fixture. |
| T11 | R5 | browser | From the origin page, `fetch` PROPFIND with Basic auth. | Request succeeds and the response is readable. |
| T12 | R5 | browser | From the origin page, PUT, GET and DELETE with auth; read `ETag` from each response. | All succeed; `response.headers.get('ETag')` is non-null on PUT and GET. *Amended 2026-10-02: originally required on DELETE too, but Nextcloud sends no ETag on DELETE responses even to same-origin clients and remoteStorage.js never reads one, so that clause tested nothing CORS-related and was unsatisfiable.* |
| T13 | R5 | browser | Repeat T7 from the browser. | 412 is visible to the page, not masked as a network error. |
| T14 | R6 | browser | POST `/index.php/login/v2` from the origin; approve the login in a second Nextcloud tab; poll the endpoint from the origin. | Page receives `server`, `loginName` and `appPassword`; the app password works for T11. |
| T15 | R6 | browser | *Added 2026-10-02.* From the origin page, a user click opens `/index.php/apps/webapppassword/?target-origin=<origin>` in a popup; log in there; wait for `postMessage` on the opener; PROPFIND with the received token; then load the same URL with a foreign `target-origin`. | Opener receives `{type: "webapppassword", loginName, token, webdavUrl}` from the Nextcloud origin; the token works for T11; the foreign origin gets 403 and no token. Record the token's lifetime (`scripts/token-lifetimes.sh`). |

Expected matrix: T1–T10 pass on every variant. T11–T15 fail on `stock`; the `webapppassword` and `pr40537` results are the main finding. In T14, approving the login is the step an LLM browser agent may need to drive.

## LLM runbook

An agent with a shell, Docker and Playwright follows these steps unattended and stops only at the conditions listed.

1. **Build the harness** if it doesn't exist yet: `compose.yaml`, `setup/<variant>.sh`, `probes/curl/*.sh` (T1–T10), `origin/probe.html` and `runner/probe.spec.ts` (T11–T15).
2. **Pick the matrix.** Default: the latest two Nextcloud major versions × `stock` and `webapppassword`. Add `pr40537` only if the branch builds.
3. **For each version × variant:**
   1. `docker compose down -v`, then `up -d` with that version.
   2. Wait for `occ status` to report `installed: true`, timeout 5 minutes.
   3. Run `setup/<variant>.sh`.
   4. Run the curl probes, then the Playwright spec.
   5. Save `results/<version>-<variant>.json` and `docker compose logs nextcloud`.
4. **Triage every non-pass.** Re-run the case once. If it is an `error`, fix the harness and re-run. If it is a `fail`, keep the raw headers as evidence and do not "fix" Nextcloud config beyond what the variant defines.
5. **Write the report:** a results matrix (case × version × variant), then one paragraph per failure with its evidence, then the verdict on options A and B.

**Stop and ask a human when:**

- The same case is `error` three times in a row.
- A variant needs a Nextcloud setting not listed in its setup script; that changes what is being tested.
- Login Flow approval can't be automated after two attempts.
- Any step would publish, push or post anything outside the local machine.

**Don't:** loosen pass criteria to make a case pass, run against any Nextcloud other than the local container, or use real credentials.

## Reporting

Post the full report to remoteStorage and a short CORS-only version to Nextcloud; each audience needs a different slice.

| Where | What to post | Why they care |
| --- | --- | --- |
| [remotestorage.js #1320](https://github.com/remotestorage/remotestorage.js/issues/1320) | Full report and a link to the harness repo | Your open issue; raucao offered help with new backends. |
| [Forum thread 797](https://community.remotestorage.io/t/issues-with-using-webdav-as-a-back-end/797) | Summary of R1–R4 results | Answers Doug Reeder's unanswered lowest-common-denominator question for Nextcloud. |
| [remotestorage.js #1093](https://github.com/remotestorage/remotestorage.js/issues/1093) | One-line link to the report | Tests raucao's Nextcloud-specific suggestion; coderofsalvation asked for this. |
| [nextcloud/server PR #40537](https://github.com/nextcloud/server/pull/40537) | T11–T14 results on the PR build, if run | A concrete downstream client and an independent test of the PR. |
| [nextcloud/server #3131](https://github.com/nextcloud/server/issues/3131) | T11–T14 on stock and WebAppPassword, with the `ETag` exposure finding | Real use case with evidence, rather than another +1. |

Frame the Nextcloud posts as "remoteStorage.js speaking Nextcloud WebDAV," not "Nextcloud as a remoteStorage server." #843 and #12686 already declined the second.

## Open questions

- [x] Is PR #40537 still a draft, and does it build against current Nextcloud? — Still a draft. The branch is based on 28.0.0 dev, not master, so it does not run against current Nextcloud; it also has a fatal `Undefined constant "OCA\DAV\IUserSession"` in `apps/dav/lib/Server.php` (missing `OCP` imports). With the DAV subset applied to 28.0.14.1 and that fixed, it matches WebAppPassword (T11–T13 pass). Its preflight answers `Access-Control-Allow-Origin: *` for any origin; only the actual response checks the allow-list.
- [x] What is WebAppPassword's exact config key for allowed origins, and does it expose `ETag`? — App value `origins`, set with `occ config:app:set webapppassword origins --value=http://origin`. It exposes `ETag` on PUT and GET via `Access-Control-Expose-Headers: etag, dav`; DELETE responses carry no ETag.
- [x] Does Nextcloud folder ETag propagation ever lag on write (T4)? — No. The root ETag had changed on the first PROPFIND after PUT returned in every run (171–216 ms including the request).
- [x] Scoping (R7): recommend a dedicated Nextcloud user, a dedicated folder, or accept full-account access? — Dedicated Nextcloud user. App passwords are account-wide; a dedicated folder in a shared account is only acceptable if the user accepts account-wide access.
- [x] Which Nextcloud major versions go in the default matrix? — The latest two majors, 35 and 34, each with `stock` and `webapppassword`. The PR variant runs separately on its matching 28.x base.
- [x] Does the remoteStorage.js backend interface need anything beyond what the Dropbox and Google Drive backends implement? Read their source before prototyping. — No. `configure`/`connect` plus `get`/`put`/`delete`; folder listings are returned by `get()` as an item map with a per-child `ETag` and the folder ETag as `revision`. Their item-URL and share-link hooks are optional.

## Results

Run 2026-10-02: Nextcloud 35.0.1 and 34.0.4 × `stock`/`webapppassword`, plus PR #40537 on 28.0.14.1. R1–R4 pass on stock; R5 fails on stock (preflight rejected with 401, no CORS headers) and passes with WebAppPassword; R6 via Login Flow v2 (T14) fails everywhere, but via WebAppPassword's popup flow (T15, added after the first runs; run 6) it passes on both WebAppPassword configurations, with 24-hour tokens; three consecutive runs produced identical statuses for all 70 case-results, confirmed by hand with browser-faithful `curl`. T12's criterion was amended (see the test table) after the runs showed the DELETE clause could never pass on any server configuration. Full write-up: [`REPORT.md`](REPORT.md); raw evidence in `results/`.

## Sources

- [remotestorage.js #1093](https://github.com/remotestorage/remotestorage.js/issues/1093), [#1320](https://github.com/remotestorage/remotestorage.js/issues/1320), [#1280](https://github.com/remotestorage/remotestorage.js/issues/1280)
- [remotestorage spec #136](https://github.com/remotestorage/spec/issues/136), [#137](https://github.com/remotestorage/spec/issues/137)
- [remoteStorage forum: Issues with using WebDAV as a back-end?](https://community.remotestorage.io/t/issues-with-using-webdav-as-a-back-end/797)
- [Armadietto](https://github.com/remotestorage/armadietto/) and its [modular server notes](https://raw.githubusercontent.com/remotestorage/armadietto/HEAD/notes/modular-server.md)
- [nextcloud/server #3131](https://github.com/nextcloud/server/issues/3131), [#843](https://github.com/nextcloud/server/issues/843), [#37716](https://github.com/nextcloud/server/issues/37716), [PR #40537](https://github.com/nextcloud/server/pull/40537)
- [owncloud/core #12686](https://github.com/owncloud/core/issues/12686)
- [Nextcloud forum: WebAppPassword CORS report](https://help.nextcloud.com/t/accessing-files-with-a-js-webapp-hosted-on-another-domain-by-webdav-or-any-other-mean-is-it-possible/181932)
