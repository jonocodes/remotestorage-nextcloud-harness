# B3u · RS Inspektor (upstream, raucao) — session notes (2026-10-08)

Client: **upstream RS Inspektor**, `raucao/inspektor` (<https://gitea.kosmos.org/raucao/inspektor>)
@ `0bece35` (2023-09-20), Ember 2.16, `remotestoragejs` **1.1.0**, `remotestorage-widget` 1.3.0.
It constructs `new RemoteStorage({ cache: false })` (`app/services/storage.js`).
Stack: Nextcloud 35.0.1.1 (apache), app `remotestorage` 0.3.0 (`273df2b`). Built with
`ember build --environment=production` in `node:8` (compose service
`inspektor-upstream-build`), `dist/` served statically by Caddy with an SPA fallback (service
`inspektor-upstream`), loaded by the browser as `http://localhost:8082` via the `loopback`
proxy. Driven by the pinned Playwright image.
Run: `explore/clients/inspektor-upstream/run.sh` → `result.json` (pass), `artifacts/*.png`,
`artifacts/observed.json`.

This session exists because B3 (`../inspektor/notes.md`) tested **m5x5/inspektor**, a 2026
Next.js rewrite of this app. Its metadata loss came from `cache: true`, which m5x5's rewrite
introduced (commit `6313ce6`). It is not in upstream.

## Result

**Pass, with full metadata.** Upstream Inspektor connects with scope `*`, browses the account,
renders JSON as a tree, shows the server's Content-Type, size and ETag for every file, previews
an image, and deletes a document through its own UI. Ran twice, both passes.

| Step | Evidence |
| --- | --- |
| Connect | widget 1.3.0 (plain DOM, `skipInitial`) → `rstest@nextcloud` → login → consent |
| Browse root | `02-root.png`: module `b3/` (fresh stack) |
| `/b3/` listing | sizes and types per item: `hello.json` 35 bytes `application/json`, `notes.txt` 15 bytes `text/plain`, `pic.png` / `pic-rsjs.png` 70 bytes `image/png`, `sub/` folder |
| Open JSON | `03-json.png`: **tree view** (`content: Object[2]`, `greeting: "hi"`, `nested: Object[1]`, `n: 42`) |
| Open image | `04-image.png` (`pic.png`): **no preview**. `04b-image-rsjs.png` (`pic-rsjs.png`): **preview renders** (`<img src="blob:…">`, 1×1 natural size) |
| Delete | trash button + `confirm()` → `notes.txt` gone from the server listing (`05-deleted.png`) |

## Metadata outcome (the key observation)

The File info panel showed exactly what the server's folder listing returns:

| File | Content type | Size | Revision (ETag) |
| --- | --- | --- | --- |
| `hello.json` | `application/json` | 35 bytes | the server's ETag |
| `pic.png` | `image/png` | 70 bytes | the server's ETag |
| `pic-rsjs.png` | `image/png` (stored as `image/png; charset=binary`) | 70 bytes | the server's ETag |
| `notes.txt` | `text/plain` | 15 bytes | the server's ETag |

ETags match the `*:rw` token listing byte for byte (`artifacts/server-listing-b3.json` vs
`artifacts/observed.json`). With `cache: false`, rs.js 1.1.0's `getListing` returns the full
item objects, so nothing is lost. The `application/octet-stream` / blank size / blank ETag
result in B3 is specific to m5x5's rewrite with `cache: true`. Upstream Inspektor does not
have it, and the app does not cause it.

## Finding: the image preview depends on `charset=binary` (client heuristic)

Upstream marks an item binary only if its Content-Type contains `charset=binary`
(`storage.js`: `isBinary = !!type.match(/charset=binary/)`). Only binary items get an `<img>`
(`file-preview` template). rs.js 1.x adds `; charset=binary` when it PUTs an ArrayBuffer
(`wireclient.js` `put`), so images written by rs.js apps preview and images written by
other clients as plain `image/png` do not. To show both cases, this run seeds the same tree as
B3 plus `pic-rsjs.png`, stored the way rs.js stores binaries:

- `pic.png` (`Content-Type: image/png`, as B3 seeds it): metadata correct, **no `<img>`**.
  The item is treated as text and the preview area is an empty `<code>` block.
- `pic-rsjs.png` (`Content-Type: image/png; charset=binary`): **preview renders**.

The app stores and returns the full Content-Type with its `charset=binary` parameter, so this
is upstream's heuristic and has nothing to do with the app. Any server gives the same result
for a PNG uploaded without the parameter. The test still checks that the app serves the PNG
bytes (signature `89 50 4E 47`).

## Notes / gotchas

- **Build.** It builds unmodified, with no hacks: `npm ci` from the committed lockfile v1 in
  `node:8` (Node 8.17, npm 6.13), then `ember build --environment=production`.
  `node-sass` 4.6.0 downloads its prebuilt `linux-x64-57` binding from GitHub, and the two
  `github:` dependencies (`ember-cli-bourbon`, `skddc/json-tree-view#bugfix/setters`) still
  resolve. The first `npm ci` took about 7 minutes. There is no `bower.json`.
- **History URLs.** `locationType: 'auto'`, so `/connect` and `/inspect?path=…` need the SPA
  fallback (`explore/clients/inspektor-upstream/Caddyfile`: `try_files {path} /index.html`).
  The spec navigates by clicking links inside the app, not with `page.goto`, because the
  `inspect` route doesn't wait for the connection to restore.
- **Loopback origin.** The app accepts plain-http OAuth redirect URIs only on loopback hosts,
  so this client is reached as `http://localhost:8082` through the `loopback` service
  (`origin/loopback.Caddyfile`), not as `http://inspektor-upstream`.
- **Widget 1.3.0** is plain DOM, so the shadow-root override from B3 isn't needed. The
  connect button is `input.rs-connect`.
- **WebFinger.** webfinger.js 2.7 tries `https://nextcloud` first. The three
  `ERR_CONNECTION_REFUSED` console errors are from those attempts, before it falls back to
  http.
- **Delete** uses `window.confirm('Delete?')`, which the spec accepts with a dialog handler.

## Reproduction

```sh
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/inspektor-upstream/run.sh    # builds dist/ in node:8 if needed
```
