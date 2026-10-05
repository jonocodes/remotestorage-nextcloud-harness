# C1 · spec-check — session notes (2026-10-05)

Suite: `0dataapp/spec-check` @ `e969675` (a browser + Node/mocha conformance suite for the
remoteStorage REST API). Run in `client-probe` (Node 20) against the app; it discovers the
spec version from WebFinger and uses three app tokens.
Stack: Nextcloud 35.0.1.1 (apache), app `remotestorage` 0.2.0 (`be660b2`).
Run: `explore/clients/spec-check/run.sh` → `result.json` (pass), `artifacts/mocha.json`.

## Result

**66 passing, 6 pending, 4 failing — every failure is known and explained.** A second
conformance data point alongside AT11's community `api-test-suite`. (The first run was
64/6/6; the two DELETE-ETag cases below were fixed and now pass.)

Tokens: `api-test-suite:rw`, `api-test-suite:r`, `*:rw` (issued with
`occ remotestorage:token:issue`). WebFinger reported `draft-dejong-remotestorage-22`, so the
suite ran its version-22 checks (folder-description listings, `Last-Modified`, `Cache-Control`,
conditional headers, binary, ranges, root/scope/public folders, OPTIONS/CORS).

Covered and passing: OPTIONS preflight (CORS headers incl. `ETag` in
`Access-Control-Expose-Headers`), empty/read-only/scope/root token enforcement, create/read/
update/delete, `If-Match`/`If-None-Match`, `Content-Range`, binary file, list, root folder,
public folder with and without a token.

## The 4 failures

**4 × "other user rejects HEAD/GET/PUT/DELETE" — vacuous test for this app's URL shape.**
spec-check tries to retarget another account by replacing `/<account>` at the *end* of the
base URL (`generate.js:91-99`). Our storage URL is
`…/remote.php/dav/files/rstest/remoteStorage` — it ends in `/remoteStorage`, so the regex
never matches, the URL is unchanged, and the test actually re-tests **rstest's own account**
(hence 404 for reads and 201 for PUT, not 401/403). Not an app issue. Cross-user rejection was
verified directly instead:

```
rstest *:rw token → /files/rsbackup2/remoteStorage/probe.txt
  GET 403   HEAD 403   DELETE 403   PUT 403      (nothing written to either account)
```

**Fixed (was "delete {without,with} folder removes file").** spec-check (spec ≥ 2) expects the
deleted item's ETag on the DELETE response; Nextcloud core sends none. The app now returns it
(`RsPlugin::rememberDeleteETag` + `afterDelete`), so both cases pass. This was the only
app-side gap the exploration found.

## Notes

- **6 pending**: the "public folder → wrong scope" cases are skipped in the Node runner.
- The suite assumes a 5apps-style storage URL (`host/<account>`), so any test that rewrites
  the account segment cannot work against a path-embedded user; worth reporting upstream.
- dotenv prints a banner line before the JSON reporter output; the runner strips it.

## Reproduction

```sh
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/spec-check/run.sh
```
