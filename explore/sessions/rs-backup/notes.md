# A2 · rs-backup / rs-restore — session notes (2026-10-05)

Client: `rs-backup` 1.10.0 (`raucao/rs-backup`), webfinger.js **2.7.1**, Node 20.
Stack: Nextcloud 35.0.1.1 (apache), app `remotestorage` 0.2.0 (`be660b2`), variant `rsapp`.
Run: `explore/clients/rs-backup/run.sh` → `result.json` (9/9 pass), `run.log`.

## Result

**Pass.** rstest's storage root was backed up via WebFinger discovery and restored into a
brand-new account; all four files byte-identical and Content-Types preserved.

| Check | Result |
| --- | --- |
| Discovery from Node (webfinger.js 2.x, `tls_only:false`, http fallback) | pass — `rstest@nextcloud` resolves over plain http |
| Recursive backup (nested folder, 4 files) | pass |
| Restore into a fresh account | pass |
| Bytes | pass — md5 equal on all four |
| Content-Type | pass — including `typed.json` stored (via app token) as `text/plain`, not the `.json` guess |
| Empty folders | `notes/empty` absent from backup (listings omit empty folders per spec) — recorded, expected |
| `000_folder-description.json` sidecars | present in the backup, not restored as documents |

How Content-Type survives: rs-backup archives each folder's `folder-description` JSON
(which carries `Content-Type`) as `000_folder-description.json`; rs-restore reads it and
re-sends the type. So round-trip metadata comes for free from the app's listings.

## Findings

1. **Core race on a brand-new user's first DAV requests.** Restoring into a user whose home
   storage had never been provisioned produced
   `SQLSTATE[23000] ... UNIQUE constraint failed: oc_storages.id` (and follow-on 423s).
   Trace: `OCA\RemoteStorage\Dav\TokenAuth::login → OC_Util::setupFS → SetupManager::oneTimeUserSetup`,
   i.e. the app uses the normal per-request login path; Nextcloud's lazy home-storage
   creation is not concurrency-safe. Worked around in the script by warming the target
   storage with one serial request (and clearing the target) before restore; a fresh account
   then passes first time. Not an app bug, but a first-connection hazard for clients that
   fire their first requests in parallel. Candidate upstream finding.
2. **rs-backup 1.10.0 is broken on Node 20 as published.** It depends on `webfinger.js ^2.7.1`,
   which resolves to 2.8.2 — `"type": "module"` / ESM-only — while rs-backup `require()`s it,
   throwing `TypeError: Cannot set properties of undefined (setting 'WebFinger')`. Fixed by
   pinning `webfinger.js@2.7.1` (last CJS release) via an npm override in
   `docker/client-probe/package.json`. Candidate upstream finding (dependency range).
3. Empty folders are invisible to any client that relies on listings (a spec consequence,
   already noted in the app README's folder semantics). rs-backup's sidecar cannot recover
   them, because the app omits empty subfolders from the listing in the first place.

## Reproduction

```sh
# stack up + app installed, then:
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/rs-backup/run.sh
```
