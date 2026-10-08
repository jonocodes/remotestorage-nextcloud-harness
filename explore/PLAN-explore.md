# Exploratory client testing against the remoteStorage Nextcloud app: Plan

Oct 5, 2026 · @Jono (plan drafted with agent assistance)

> Third track, alongside [`PLAN.md`](PLAN.md) (stock Nextcloud / WebAppPassword) and
> [`PLAN-app.md`](PLAN-app.md) (the thin app). `PLAN-app.md` proves the *protocol* with
> AT1–AT12 and a minimal remoteStorage.js page. This plan asks the next question:
> **do real, third-party remoteStorage clients work unchanged against the app?** It is
> exploratory and LLM-run, but recorded so it stays repeatable.
>
> Motivation: the outreach drafts are on hold pending "tested by hand"
> (`drafts/README.md`). This is that step, done with real clients instead of a checklist.

## Goal

Connect a set of real remoteStorage clients to the app running in this harness, exercise
each one's core workflow, verify the data through Nextcloud itself, and capture evidence
strong enough to cite in the forum posts. Exploratory, not conformance: conformance is
already AT1–AT12 and the community `api-test-suite` (AT11).

## Decisions (locked 2026-10-05)

- **Non-browser clients first**, then browser apps.
- Non-browser order: **A2 rs-backup → A1 remotestorage-fuse → A3 remote-storage-uploader**.
- Browser apps, narrowed to **three**: **B1 My Favorite Drinks → B2 Notes Together →
  B3 RS Inspektor**. Runner-ups if one is unbuildable: Todonna, Leptum, Litewrite, Diffuse.
- All clients run **inside a container on the compose network** (new `client-probe`
  service), not on the host, so `nextcloud` resolves and no host FUSE/libcurl setup is
  needed.
- Evidence lives **in this harness**, under `explore/`.

## Launchpad

Reuse the existing stack: `compose.yaml` (`nextcloud` + `origin` + `runner`) and
`app/run.sh`'s setup, but run a persistent stack rather than the full matrix:

```sh
# intended; not run yet
export NC_VERSION=35 VARIANT=rsapp NC_IMAGE=nextcloud:35-apache
docker compose down -v --remove-orphans
docker compose build curl-probe runner
docker compose up -d
./scripts/wait-for-nextcloud.sh
bash setup/common.sh
bash setup/rsapp.sh
# tokens for the clients
docker compose exec -T -u www-data nextcloud php occ remotestorage:token:issue rstest '*:rw' explore
```

### New `client-probe` service (to add)

A small Node/php/fuse container, on the compose network, mounting this repo at `/harness`:

- environment like `curl-probe` (`NC_URL=http://nextcloud`, `NC_USER`, `NC_PASS`);
- `cap_add: [SYS_ADMIN]`, `devices: ["/dev/fuse"]`, `security_opt: [apparmor:unconfined]`
  for the FUSE client (podman: same idea; `--device /dev/fuse`);
- node 20+, `libfuse`/`libcurl` build deps, php-cli;
- `command: sleep infinity`.

Every non-browser client runs here, so `nextcloud` resolves and discovery works.

## Known traps (design around these; do not rediscover the hard way)

| Trap | Detail | Consequence |
| --- | --- | --- |
| Discovery blocks loopback | webfinger.js v3 (in `origin/vendor/remotestorage.js`) rejects private/loopback hosts (`isPrivateAddress`); `rstest@localhost:8080` fails | Use `rstest@nextcloud` and run clients on the compose net |
| rs-backup uses webfinger.js **2.x** | Older discovery code path; private-address behaviour may differ | Probe first; record the observed rule |
| FUSE bypasses OAuth | Takes `base_url` + root token; no WebFinger/OAuth | Tests DAV + `*:rw` directly, not the connect flow |
| FUSE rewrites MIME | FUSE writes become `application/octet-stream` (documented upstream) | Directly stresses our per-file Content-Type store and how apps read it back |
| Arbitrary module names | Apps use `myfavoritedrinks`, `documents`, `bookmarks`, … not just `notes` | Verify consent page, scope parsing, and `*` for names beyond the harness's `notes` |
| Bundled old rs.js | Each app ships its own library version | Stronger, more realistic test than the vendored beta.9 |
| localStorage collisions | Multiple rs.js instances on one origin share localStorage/IndexedDB | Serve each browser app on **its own origin/port** |

## Track A — non-browser clients (first)

### A2 · rs-backup / rs-restore

- **Source:** `raucao/rs-backup`, npm `rs-backup` 1.10.0 (Jul 2024), Node ≥14, webfinger.js 2.7.
- **What it does:** `rs-backup -u user@host -t TOKEN -o DIR` pulls the whole account to
  disk; `rs-restore -i DIR` re-uploads it. Supports passing address + token by CLI (for
  unattended runs).
- **Proves:** Node-side discovery, full-tree recursive GET/listing, restore re-PUT of every
  document and type, delete-and-refill semantics, account→account restore.
- **Risks:** webfinger.js 2.x vs 3.x difference; "backup dir is emptied first" behaviour.
- **Setup:** `npm i -g rs-backup` in `client-probe`.

### A1 · remotestorage-fuse

- **Source:** `remotestorage/fuse` (C, 2013; `rs-mount`), needs libcurl + libfuse.
- **What it does:** mounts an account as a filesystem given `base_url` + root token.
- **Proves:** real OS-level read/write/delete against the storage root; listing fidelity;
  empty-folder and prune semantics; MIME behaviour (it forces `application/octet-stream`);
  how Nextcloud's Files app and other clients see FUSE-written files.
- **Risks:** 2013 C project may need small patches to build; FUSE needs `/dev/fuse` +
  `SYS_ADMIN`. Highest value and highest setup cost — hence second.
- **Notes:** a modern alternative if it will not build: `zen-fs-remotestoragejs`
  (`weijia/zen-fs-remotestoragejs`), a JS filesystem backed by rs.js.

### A3 · remote-storage-uploader

- **Source:** PHP; repository linked from the "CLI applications" section of
  <https://remotestorage.io/apps>.
- **What it does:** uploads files to the public upload folder.
- **Proves:** anonymous `/public/…` write path (AR8) and the upload module.
- **Risks:** may assume an OAuth flow; lowest priority — keep only if A1/A2 leave public
  access unexplored. May be dropped.

## Track B — browser apps (three)

Each app is built from source, pinned, served from **its own Caddy origin/port** inside the
compose network, and driven with Playwright (`runner` image) plus a persistent control
session for exploratory work.

### B1 · My Favorite Drinks

- **Source:** `remotestorage/myfavoritedrinks`; module `myfavoritedrinks`.
- **Why:** official, minimal demo maintained by rs.js devs; baseline for current
  conventions and the connect widget.
- **Core action:** add/edit drinks; verify JSON stored, reload, second context sees it.

### B2 · Notes Together

- **Source:** `DougReeder/notes-together` (React + Vite; `npm run dev` / `build`); module
  `documents`; Litewrite-compatible.
- **Why:** real app, rich data model (text + pictures + files), non-`notes` module.
- **Core action:** create/edit/delete notes, attach an image; verify files and
  Content-Types in Nextcloud, then re-open in a second context.

### B3 · RS Inspektor

- **Source:** upstream `raucao/inspektor` (<https://gitea.kosmos.org/raucao/inspektor>, also
  `gitlab.com/skddc/inspektor`; Ember 2.16, rs.js 1.1.0, `cache: false`), tested as **B3u**;
  and `m5x5/inspektor`, a 2026 Next.js rewrite (history copied, not a fork; rs.js
  2.0.0-beta.8, `cache: true` since m5x5 `6313ce6`), tested as **B3**. Scope `*`.
- **Why:** whole-account client; tests root scope, traversal, delete, and doubles as our
  **verifier** for what A1/A2/B1/B2 wrote.
- **Core action:** connect, browse the tree written by the other clients, open a JSON doc
  and an image, delete a document.

## Cross-cutting scenario matrix

Run through every client; capture raw evidence on any miss.

| Scenario | What to check |
| --- | --- |
| Connect UX | Widget, address entry, consent wording per module, first-run wizard |
| Core action | App-specific write; then visible in Files + WebDAV (`app/snapshot.sh`) |
| Cross-client sync | A second client (browser or CLI) reads what the first wrote |
| Edit + sync | Re-read under compression, edit with `If-Match`, no false 412 (AT7i/AT12) |
| Delete + prune | File gone, emptied parents pruned (to, not including, root) |
| Content-Type round-trip | JSON/markdown/image survive PUT→GET and listings; FUSE effects |
| Awkward data | Non-ASCII names, binary, nested, empty folders, larger files |
| Revocation | Disconnect in Settings → Security and mid-session; token → 401 |
| Version / deployment | Nextcloud 34 vs 35; Apache vs `rsapp-nginx-fixed` |

## Evidence layout

```
explore/
  PLAN-explore.md            this file
  clients/                   pinned checkouts / build scripts (gitignored outputs)
  sessions/<client>/         screenshots, console log, HAR, result JSON, notes
results/app/…                existing AT evidence, unchanged
```

Pin each client by commit/version, keep the run step scripted (`explore/clients/<name>/run.sh`),
and prefer the harness's existing JSON result shape so `results/` stays diffable.

## Sequencing (LLM runbook)

1. Add the `client-probe` service; bring up a persistent stack (35/rsapp); issue a `*:rw`
   token and a `myfavoritedrinks:rw` token.
2. **A2** rs-backup: seed a small tree, backup, restore into a second user, diff.
3. **A1** FUSE: mount, list/read/write/delete, inspect Content-Types and folder pruning.
4. **B1 → B2 → B3**: build and serve each app on its own origin; drive with Playwright;
   screenshot; cross-verify with B3.
5. **A3** only if public/upload access is still unprobed.
6. Write the findings report in the **app repo** (`TESTING.md`): per client, commit, result,
   evidence, and any upstream finding. The harness keeps the rig and the raw evidence.
7. Update this harness's `README.md` layout table with `explore/`.

**Stop and ask a human when:** a client needs a core Nextcloud change or an app-store
account; a pass would need a looser criterion; a client cannot be built after two attempts
(pick a runner-up instead); anything would be published.

## Exit criteria

Each client connects, performs its core action, the data is visible via WebDAV and in the
Files UI, and a second client sees it; delete and revoke behave; every non-pass is captured
with raw evidence and explained. No loosened criteria.

## Open questions

- [x] Which browser apps? — B1/B2/B3, runner-ups Todonna/Leptum/Litewrite/Diffuse.
- [x] Non-browser order? — A2 → A1 → A3.
- [x] Evidence home? — this harness, `explore/`.
- [ ] Is A3 (PHP uploader) worth running once A1/A2 are done?
- [ ] Does `remote-storage-uploader` have a usable non-interactive path, or does it need OAuth?
- [x] FUSE: build as-is, or fall back? — It builds and mounts, but is **functionally
      incompatible**: it parses the obsolete flat (`draft-02`) listing format, so the tree
      does not resolve (`@context`/`items` become phantom entries, every path ENOENT). See
      `sessions/remotestorage-fuse/notes.md`. Recommend a maintained substitute
      (`zen-fs-remotestoragejs`) or dropping the FS-level case.

## Session results

- **A2 rs-backup** — pass; see `sessions/rs-backup/notes.md`.
- **A1 remotestorage-fuse** — fail (stale client); see `sessions/remotestorage-fuse/notes.md`.
  **Retired 2026-10-07** (unmaintained, cannot pass); its script and evidence are at tag
  `archive/explore-remotestorage-fuse` (see `ARCHIVE.md`).
- **B1 My Favorite Drinks** — pass; see `sessions/myfavoritedrinks/notes.md`. Uses its own
  widget/OAuth for module `myfavoritedrinks`; add → server → reload → delete.
- **B2 Notes Together** — pass; see `sessions/notes-together/notes.md`. Module `documents`;
  a note created on device A is read from the server by a second fresh browser context and
  deleted through the app.
  **Retired 2026-10-07**: it exercised the same rs.js connect/sync/delete flow as B1, and
  two-device sync is covered by AT12; its script and evidence are at tag
  `archive/explore-notes-together` (see `ARCHIVE.md`).
- **B3 m5x5/inspektor** (2026 Next.js rewrite of RS Inspektor) — pass; see
  `sessions/inspektor/notes.md`. Scope `*`; browses the account, reads documents, deletes one.
  Client finding, specific to the rewrite: with `cache: true` (m5x5 `6313ce6`), rs.js beta.8's
  `getListing` drops Content-Type/Length (its issues 721/1108), so it shows every item as
  `application/octet-stream` and can't preview images. The app serves correct metadata.
- **B3u upstream RS Inspektor** (`raucao/inspektor` @ `0bece35`, `cache: false`) — pass; see
  `sessions/inspektor-upstream/notes.md`. Full metadata: correct Content-Type, size and ETag
  per file, JSON tree view, delete. Images preview only when stored with `charset=binary`
  (as rs.js writes them). That is upstream's own heuristic, unrelated to the app.
- **C1 spec-check** — pass; see `sessions/spec-check/notes.md`. `0dataapp/spec-check`
  (second conformance suite, alongside AT11): 64 passing, 6 pending, 6 failing, all
  explained (4 "other user" tests are vacuous for this URL shape; 2 DELETE-ETag cases are a
  known Nextcloud deviation).

## Sources

- remoteStorage apps list: <https://remotestorage.io/apps>
- remotestorage-fuse: <https://github.com/remotestorage/fuse>
- rs-backup: <https://github.com/raucao/rs-backup> · npm `rs-backup`
- Notes Together: <https://github.com/DougReeder/notes-together>
- RS Inspektor: upstream <https://gitea.kosmos.org/raucao/inspektor> (also
  <https://gitlab.com/skddc/inspektor>) · Next.js rewrite <https://github.com/m5x5/inspektor>
- My Favorite Drinks: `remotestorage/myfavoritedrinks`
- zen-fs-remotestoragejs: <https://github.com/weijia/zen-fs-remotestoragejs>
- This harness: [`PLAN-app.md`](PLAN-app.md), [`REPORT-app.md`](REPORT-app.md)
