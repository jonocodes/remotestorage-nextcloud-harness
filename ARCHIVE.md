# Archive

Retired work is kept at `archive/…` git tags rather than in the tree. Check one out with
`git checkout <tag>` (or browse it on GitHub) to see the files as they were.

| Tag | What | Retired | Why |
| --- | --- | --- | --- |
| `archive/explore-remotestorage-fuse` | A1 `remotestorage-fuse` client: `explore/clients/remotestorage-fuse/`, its session evidence, and the FUSE privileges/packages in `compose.yaml` and `docker/client-probe/` | 2026-10-07 | Unmaintained since 2013; parses the obsolete draft-02 listing format, so it can never pass. Not a signal about the app. |
| `archive/explore-notes-together` | B2 Notes Together: `explore/clients/notes-together/`, `explore/browser/explore-nt.spec.ts`, its session evidence and the `nt` service | 2026-10-07 | Exercised the same remoteStorage.js connect/sync/delete flow as B1 My Favorite Drinks; two-device sync is covered by AT12. |
