# A1 · remotestorage-fuse — session notes (2026-10-05)

Client: `remotestorage/fuse` @ `2a25a1c` (last commit 2013-era), libfuse2 2.9.9, libcurl.
Stack: Nextcloud 35.0.1.1 (apache), app `remotestorage` 0.2.0 (`be660b2`), variant `rsapp`.
Run: `explore/clients/remotestorage-fuse/run.sh` → `result.json`, `run.log`, `artifacts/`.

## Result

**Builds and mounts, but is functionally incompatible with a current remoteStorage server.**
It is a stale client, not an app defect.

| Check | Result |
| --- | --- |
| A1-build | pass — needs `-fcommon` on GCC ≥ 10 (`RS_CONFIG` multiple definition); builds otherwise |
| A1-mount | pass — root token + `base_url`; rootless-podman container with `SYS_ADMIN` + `/dev/fuse`, `mount(2)` directly, no `fusermount` |
| A1-list-root | **fail** — `ls /mnt/rs` → `@context`, `items` (phantom entries); the real module `notes` is absent |
| A1-list-notes | fail — `/mnt/rs/notes` → ENOENT |
| A1-read | fail — `cat .../notes/hello.txt` → ENOENT |
| A1-write | fail — writing under `notes/` → ENOENT; nothing reaches the server |

## Root cause

`parse_listing` (`src/helpers.c:116`) is a flat parser: it reads the body as a single
JSON object and treats **every key at any depth as a directory entry**, using the value as
the revision. That matches the pre-`folder-description` listing format (`{ "notes/": "rev",
"hello.txt": "rev" }`, from `draft-dejong-remotestorage-02`), which the README's link
advertises.

The app returns the current spec shape:

```json
{"@context":"http://remotestorage.io/spec/folder-description",
 "items":{"hello.txt":{"ETag":"…","Content-Type":"text/plain","Content-Length":11,…}}}
```

so the parser produces entries named `@context` and `items`; `notes/` is never seen and
every path below it is ENOENT. The client's own README output (`@context foo items rss`)
shows the same artifact, so this is not specific to Nextcloud.

## Notes / non-findings

- The app's listing is spec-correct and identical to what remoteStorage.js consumes
  (AT5, AT12); the app is not at fault.
- `rel` in WebFinger is `http://tools.ietf.org/id/draft-dejong-remotestorage`, not
  `remotestorage`. remoteStorage.js maps both; a client doing strict equality would miss
  it. Not observed to matter here (this client does no WebFinger at all).
- Because listings fail at the root, the rest of the tool (read/write/delete, MIME
  handling) could not be exercised. Even patched, it writes
  `Content-Type: application/octet-stream; charset=binary` (documented upstream), which
  our app stores, so MIME stress remains a useful, separate probe.

## Recommendation

Do not count `remotestorage-fuse` as a working real-world client — it is unmaintained since
2013 and implements an obsolete listing format. For filesystem-level coverage use a
maintained implementation instead, e.g. `zen-fs-remotestoragejs` (JS, rs.js-backed) driven
by a small Node script, or drop the FS-level case. A diagnostic-only patch to
`parse_listing` is possible to check whether the app is otherwise FS-compatible, but it
would not be "the real client".

## Reproduction

```sh
export NC_VERSION=35 VARIANT=rsapp
bash explore/clients/remotestorage-fuse/run.sh
```
