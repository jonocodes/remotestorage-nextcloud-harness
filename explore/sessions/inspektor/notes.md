# B3 · RS Inspektor — session notes (2026-10-05)

Client: `m5x5/inspektor` @ `b499d16` (modernized RS Inspektor; Next.js 16, React 19,
`remotestoragejs` **2.0.0-beta.8**, `m5x5-remotestorage-widget`). Stack: Nextcloud 35.0.1.1
(apache), app `remotestorage` 0.2.0 (`be660b2`). Built and served with `next start` on its
own origin `http://inspektor` (compose service `inspektor`); driven by the pinned Playwright
image.
Run: `explore/clients/inspektor/run.sh` → `result.json` (pass), `artifacts/*.png`.

## Result

**Pass.** Inspektor connects with scope `*`, browses the whole account, reads documents,
and deletes one through its own UI. Content-type-dependent niceties are broken by a client
bug (below), not by the app.

| Step | Evidence |
| --- | --- |
| Connect | widget (scope `*`) → `rstest@nextcloud` → login → consent |
| Browse root | `02-root.png`: modules `b3`, `documents`, `notes` |
| Open JSON | `03-json.png`: `{"greeting":"hi","nested":{"n":42}}` |
| Open image | `04-image.png`: PNG bytes shown as (garbled) text |
| Delete | `05-deleted.png`; `notes.txt` gone from the server listing |

## Finding: Inspektor shows every item as `application/octet-stream`

In `03-json.png` / `04-image.png`, File info shows **Content type `application/octet-stream`,
Size `—`, Revision `—`** for every file, and so:
- images/PDF/audio/video don't preview (rendered as decoded text instead),
- JSON isn't shown as a tree (rendered as raw text),
- sizes and ETags are blank.

Root cause is in the client's stack, and **documented in rs.js itself** —
`remotestoragejs/src/baseclient.ts:314-318`:

> At the moment, this function only returns detailed metadata, when caching is turned off.
> With caching turned on, it will only contain the item names as properties with `true` as
> value. See issues 721 and 1108.

Inspektor constructs `new RemoteStorage({ cache: true })` (`lib/remotestorage.ts`) and calls
`client.getListing(path)`, so it receives `{ "hello.json": true, ... }` and falls back to
`application/octet-stream` (`lib/remotestorage.ts:70,80`). Reproduced directly:

```
$ node -e '...rs.remote.href=...; rs.remote.token=...; rs.scope("/").getListing("b3/")'
{ "sub/": true, "hello.json": true, "notes.txt": true, "pic.png": true }
```

The app is not at fault: the same account via a `*:rw` token returns full metadata —
`hello.json` `application/json`, `notes.txt` `text/plain`, `pic.png` `image/png`, with
`Content-Length`. The test therefore asserts the app serves the correct PNG bytes
(signature `89 50 4E 47`) and records the client limitation instead of failing on it.

## Notes / gotchas

- **Closed shadow DOM.** This widget is a custom element `<remotestorage-widget>` with
  `attachShadow({ mode: "closed" })`, so Playwright cannot see its controls. The spec forces
  it open via an `addInitScript` that overrides `Element.prototype.attachShadow` to
  `mode: "open"`. The widget itself is unchanged; this is a driving technique only.
- Desktop layout hides the "Document actions" menu (`md:hidden`); delete is under
  **More actions** on desktop, or "Document actions" on mobile.
- Useful as a verifier: it lists the shared account exactly as the other clients left it
  (`b3`, `documents`, `notes`), so it confirms A2/B1/B2 wrote to the server.

## Reproduction

```sh
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/inspektor/run.sh    # builds .next if needed
```
