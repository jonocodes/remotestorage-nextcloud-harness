# B1 · My Favorite Drinks — session notes (2026-10-05)

Client: `remotestorage/myfavoritedrinks` @ `b51503e` (official rs.js demo, static, bundles its
own rs.js + widget). Stack: Nextcloud 35.0.1.1 (apache), app `remotestorage` 0.2.0
(`be660b2`). Served on its own origin `http://mfav` (compose service `mfav`); driven by the
pinned Playwright image in the `runner` service.
Run: `explore/clients/myfavoritedrinks/run.sh` → `result.json` (pass), `artifacts/*.png`.

## Result

**Pass.** The app's own connect widget (remoteStorage widget → WebFinger discovery → Nextcloud
login → consent) works unchanged, and a drink round-trips through the server.

| Step | Evidence |
| --- | --- |
| Widget connect | `01-loaded`, `02-widget-address`; address `rstest@nextcloud` |
| Consent | `03-consent`: "Connect http://mfav?" … `myfavoritedrinks — read and write` … Allow/Deny |
| Connected | `04-connected`; `window.remoteStorage.connected === true` |
| Add + server write | `05-drink-added`; module listing has one doc, body `{"name":"Coffee"}` |
| Reload (second device) | `06-after-reload`; drink rendered from the server |
| Delete | `07-deleted`; module empty |

Stored shape: `/myfavoritedrinks/<timestamp>` JSON `{"name":"…"}`, `Content-Type:
application/json` (the app's `storeObject`).

## Notes / non-findings

- `ERR_CONNECTION_REFUSED` x3 in `console.log` are rs.js discovery trying https first
  (webfinger, host-meta, host-meta.json) before falling back to http — the harness has no
  TLS. Expected, benign; discovery then succeeds (`WebFinger: Server uses
  "application/json"…`).
- The widget in this build opens the sign-in box directly (no "choose provider" step); the
  flow is a top-level redirect, not a popup.
- The app requests module `myfavoritedrinks` (not `notes`), exercising an arbitrary module
  name end to end — the consent page and scope enforcement handle it.

## Reproduction

```sh
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/myfavoritedrinks/run.sh
```
