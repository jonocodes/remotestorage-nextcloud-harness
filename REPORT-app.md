# Can a thin Nextcloud app make Nextcloud a remoteStorage server?

**Test report — 2026-10-03 · @Jono (app, harness and runs with agent assistance)**

Status: **reviewed 2026-10-03; posted to remotestorage.js #1320.** Companion to [`PLAN-app.md`](PLAN-app.md)
(the plan and its dated results) and to [`REPORT.md`](REPORT.md) (what stock Nextcloud and
WebAppPassword can do). The app is
[jonocodes/nextcloud-remotestorage](https://github.com/jonocodes/nextcloud-remotestorage);
everything here is reproducible with this repository.

## Summary

- **Yes.** A small Nextcloud app (about 1,700 lines of PHP including comments and templates, no core patches) makes Nextcloud a
  remoteStorage server that existing remoteStorage apps use unchanged. The admin instruction:
  *install the app*; on nginx, also add two small blocks to its config (below).
- **Unmodified remoteStorage.js 2.0.0-beta.9 works end to end** on Nextcloud 34 and 35: connect
  from `user@host` (WebFinger, Nextcloud login, consent page), sync into nested folders, a second
  device syncs down and edits after a compressed read without a conflict, delete prunes the
  emptied folders, and the file is a normal Nextcloud file throughout.
- **The community server suite**
  ([remotestorage/api-test-suite](https://github.com/remotestorage/api-test-suite)) passes 52 of
  53 tests behind Apache. The one failure is a false positive caused by Nextcloud core's session
  cookies. Behind nginx it does too, once its config has the two additions below.
- **Normal WebDAV is unchanged** with the app enabled (Basic-auth responses compared before and
  after), and the app works alongside WebAppPassword.
- **Building it surfaced problems in Nextcloud and remoteStorage.js** that affect other clients
  too; see [Upstream findings](#upstream-findings). The app works around each of them for its
  own requests, using public API only.

## Results

Nextcloud 35.0.1 and 34.0.4 (official images, SQLite), app 0.2.0, remoteStorage.js
2.0.0-beta.9, Chromium (Playwright 1.63). Each cell is identical on 34 and 35. Three consecutive
full runs gave identical statuses, except that the nginx-fixed config gained its gzip line
after the first (which turned its AT11 from fail to pass). The committed evidence is from the
third run, against app commit `be660b2`.

| Cases | Apache | Apache + WebAppPassword | nginx, official config | nginx, with the two additions |
| --- | --- | --- | --- | --- |
| AT1a–d WebFinger, AT2 consent, AT3 scopes, AT4 browser CORS, AT5 listings, AT6 parents, AT7 conditionals, AT8 propagation, AT9 public, AT10 non-interference, C/A checks | pass | pass (+ W1–W2 coexistence) | pass | pass |
| AT1e–f WebFinger without a redirect, CORS on every response | pass | pass | **fail** (301) | pass |
| AT11 community suite (52/53; the one is a documented false positive) | pass | pass | **fail** (+2: weak folder ETags from gzip) | pass |
| AT12 remoteStorage.js, two devices | pass | pass | **fail** (discovery) | pass |
| **Total** | **67/67** | **69/69** | 63/67 | **67/67** |

The nginx failures are the deployment issue the two config additions fix; the app needs no
change for them.

## The admin instruction

1. Install and enable the `remotestorage` app (not yet in the app store; see the app's README).
2. Apache: nothing else. nginx with Nextcloud's documented config: add, inside its
   `location ^~ /.well-known { ... }` block,

   ```nginx
   location = /.well-known/webfinger {
       rewrite ^ /index.php/.well-known/webfinger last;
   }
   ```

   because that config answers WebFinger with a 301 redirect, which remoteStorage.js cannot
   follow in a browser (below); and, at the top of its `location ~ \.php(?:$|/) { ... }` block,

   ```nginx
   if ($http_authorization ~ "^Bearer rs_") {
       gzip off;
   }
   ```

   because nginx turns the ETags of compressed responses weak, and remoteStorage requires strong
   ones.

Users find their address (`user@host`) in Settings → Security, where connected apps are listed
and can be disconnected.

## How the app works

It fills only the gaps between Nextcloud's WebDAV and the remoteStorage protocol, through
public extension points: a WebFinger handler (`IHandler`), an OAuth consent page (implicit
grant) issuing its own scoped `rs_…` tokens, a DAV auth backend (`SabrePluginAuthInitEvent`) that
logs requests in for that request only, and a WebDAV plugin (`SabrePluginAddEvent`). Every file
operation stays with Nextcloud: versions, trash, quotas, the Files UI and the desktop client see
ordinary files in each user's `remoteStorage/` folder. Scopes are enforced by the app, so a
`notes:rw` token reaches `/notes/` and `/public/notes/` and nothing else — which Nextcloud's own
app passwords cannot do (REPORT.md R7).

## Findings

### Where Nextcloud's WebDAV differs from remoteStorage

Found by the harness and the community suite, each corrected by the app for remoteStorage
requests only:

| Difference | Effect on a remoteStorage client | What the app does |
| --- | --- | --- |
| Content-Type is guessed from the file name, not stored | `.json` sent as `application/json` comes back `text/plain`; parameters are lost | Stores the PUT's Content-Type per file id and ETag; applies it while the ETag is current |
| File ETag = md5(mtime in whole seconds, inode, device, size) | Two same-size writes within one second share an ETag: `If-Match` cannot detect the second, a silent lost update | After such a PUT, sets a fresh ETag and propagates it (`ICache::update`, `IPropagator`) |
| Apache `mod_deflate` appends `-gzip` to ETags; nginx makes them weak | Browsers always ask for compression; the next `If-Match` gets 412, a false conflict | Strips `-gzip`/`W/` from `If-Match`/`If-None-Match`; disables compression on Apache + mod_php |
| Overwrite and DELETE answer 204 | The spec lists 200/201 | Answers 200 |
| Missing folder → 404 (also from Files_Trashbin's `afterMethod:GET` hook) | The spec: empty folders list as `{}` | Lists missing and empty folders as empty; hides empty subfolders |
| PUT into a missing folder → 409 | The spec: parents are created silently | Creates parents; DELETE prunes emptied ones |
| WebDAV needs credentials on preflights; no CORS | Browsers cannot call it | Answers preflights before auth; echoes the origin, never allows credentials |

### Deployment

- **Apache** (official `nextcloud:*-apache` images): works as shipped.
- **nginx** with Nextcloud's documented config: everything works except discovery, because
  `/.well-known/webfinger` is answered with a 301 to `/index.php/...` and remoteStorage.js cannot
  follow redirects (below). Adding CORS to the redirect does not help; serving it with an
  internal `rewrite` does. nginx also gzips JSON and makes compressed responses' ETags weak
  (`W/`), which the suite flags on folder listings; turning gzip off for `rs_` token requests
  fixes that (variant `rsapp-nginx-fixed`, both changes, all cases pass).
- **With WebAppPassword installed:** no conflict; exactly one `Access-Control-Allow-Origin` per
  response.

### Upstream findings

Worth reporting to the projects concerned, independent of this app:

| Project | Finding | Evidence |
| --- | --- | --- |
| Nextcloud server | Local storage file ETags collide for same-size writes within one second (`Local::calculateEtag`), so `If-Match` misses concurrent edits | AT7k; suite "updating that JSON object" before the app's fix |
| Nextcloud server / docs | Default Apache `mod_deflate` config changes ETags (`-gzip`) and Sabre does not accept them back in `If-Match`; WebDAV conditional requests after a compressed GET fail with 412 | AT7i; manual check in this report's runs |
| Nextcloud server (Files_Trashbin) | `TrashbinPlugin::httpGet` (an `afterMethod:GET` hook) calls `getNodeForPath` without handling `NotFound`, overriding other plugins' successful responses | stack trace in the 2026-10-03 run |
| Nextcloud docs (nginx) | The documented config redirects `/.well-known/webfinger`; browser WebFinger clients that do not follow redirects (remoteStorage.js) cannot discover the server | variants `rsapp-nginx` vs `rsapp-nginx-fixed` |
| Nextcloud docs (nginx) | The documented config gzips JSON and XML, and nginx makes compressed responses' ETags weak (`W/`); WebDAV `If-Match` with a weak ETag fails, and clients relying on strong ETags misbehave | suite on `rsapp-nginx` (weak folder ETags) |
| Nextcloud server | `IThrottler::sleepDelayOrThrowOnMax()` no longer sleeps in 34/35 (it returns the delay); apps calling it expecting a delay get none | A3, Throttler.php |
| Nextcloud (firstrunwizard) | The first-run wizard opens over any page a new user lands on first, including app consent pages | AT2a/AT12 logs |
| remoteStorage.js (webfinger.js 3) | WebFinger fetches use `redirect: "manual"`, which browsers turn into an opaque response, so any WebFinger redirect breaks discovery, CORS or not | `rsapp-nginx` browser log |

### Security checks

Request-only logins (cookies from a token request log nobody in), non-`rs_` bearer tokens passed
through untouched and unthrottled, failed `rs_` tokens throttled and then blocked, scopes
enforced (403), nothing outside the storage root reachable, anonymous access limited to public
documents, the consent page refusing a `client_id` that is not the redirect's origin, revocation
taking effect immediately. One suite test flags anonymous 401s as differing between existing and
missing public folders; the only difference is the random session cookie Nextcloud core sets on
every response.

## What is not done

- OAuth code flow with PKCE: not built, because remoteStorage.js uses the implicit grant for
  remoteStorage servers and the spec defines no token-endpoint discovery; revisit when clients
  support it.
- The first-run wizard over the consent page (a new user closes it once).
- App-store publication (needs a signing certificate).
- Tested on the official Docker images with SQLite only; MySQL/PostgreSQL, object storage and
  encryption are untested.

## Reproduction

```sh
git clone https://github.com/jonocodes/remotestorage-nextcloud-harness.git
git clone https://github.com/jonocodes/nextcloud-remotestorage.git
cd remotestorage-nextcloud-harness
VARIANTS="rsapp rsapp+webapppassword rsapp-nginx rsapp-nginx-fixed" ./app/run.sh
```

Results: `results/app/<version>-<variant>-checks.json` (HTTP checks, AT10, AT11),
`-browser.json` (AT2, AT4, AT12), `-api-test-suite.txt` (raw suite output),
`-snapshot-*.txt` (AT10), `-app-version.txt` (app commit under test), `-nextcloud.log`.
