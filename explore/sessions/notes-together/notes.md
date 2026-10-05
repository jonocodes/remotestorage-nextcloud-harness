# B2 · Notes Together — session notes (2026-10-05)

Client: `DougReeder/notes-together` @ `321c5a1` (v0.3.3, React 18 + Vite 6 + MUI + Slate,
pinned `remotestoragejs` + `remotestorage-widget` git deps). Stack: Nextcloud 35.0.1.1
(apache), app `remotestorage` 0.2.0 (`be660b2`). Built `dist/` served on its own origin
`http://nt` (compose service `nt`); driven by the pinned Playwright image.
Run: `explore/clients/notes-together/run.sh` → `result.json` (pass), `artifacts/*.png`.

## Result

**Pass.** The app connects with its own widget/OAuth for module `documents`, writes a note
that appears on the server as a documents-module object, reads it back in a **second, fresh
browser context**, and deletes it through its own UI.

| Step | Evidence |
| --- | --- |
| Connect | widget → provider chooser → `rstest@nextcloud` → login → consent (`documents — read and write`) |
| Create + type | `03-note-typed.png`: "Hello from Notes Together" in the editor |
| Server write | `documents/notes/<uuid>` JSON, `Content-Type: application/json; charset=UTF-8` |
| Second device | `04-second-device.png`: widget shows `rstest@nextcloud / Synced`; note listed from the server |
| Delete | `05-deleted.png`; the note is gone from the listing |

Stored object (documents module):

```json
{"id":"<uuid>","mimeType":"text/html;hint=SEMANTIC","title":"Hello from Notes Together",
 "content":"<h1>Hello from Notes Together</h1><p></p>","date":"…","isLocked":false,
 "lastEdited":…,"@context":"http://remotestorage.io/spec/modules/documents/note"}
```

So the app exercises: a custom `documents` module, JSON objects with a `@context`, a
`Content-Type` that includes parameters (`application/json; charset=UTF-8`), and a
subfolder (`documents/notes/savedSearches/` is used for tags).

## Notes / gotchas

- **Widget provider chooser.** This app calls `setApiKeys({googledrive, dropbox})`, so the
  widget shows the choose-provider box before sign-in (unlike B1). The flow must click
  `button.rs-choose-rs`; state transitions are animation-timed, so wait for
  `.rs-box-choose.rs-selected` / `.rs-box-sign-in.rs-selected`.
- **Connected state is hidden.** The widget collapses when connected, so assert the
  `rs-state-connected` class (or the app's own `remoteStorage connected` console log), not
  element visibility.
- **Slate + automation.** Fast `keyboard.type` dropped/scrambled characters into the
  contenteditable editor; `locator.pressSequentially(text, {delay: 120})` worked. A test
  artifact, not an app/server issue.
- A first-launch blank starter note (`<h1></h1><p></p>`) is also synced; harmless.

## Reproduction

```sh
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/notes-together/run.sh    # builds dist/ if needed
```
