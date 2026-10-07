import { test, expect } from "@playwright/test";

// PLAN-app.md client check: unmodified remoteStorage.js against the rsspike
// app. Runs only on the rsspike variant; the token is the spike's app-config
// token (the spike has no OAuth page yet).
const ORIGIN_URL = process.env.ORIGIN_URL ?? "http://localhost";
const VARIANT = process.env.VARIANT ?? "unknown";
const TOKEN = process.env.RS_TOKEN ?? "spike-token-notes-rw";

test.skip(VARIANT !== "rsspike", "rsspike variant only");

test("SC1 remoteStorage.js discovers, writes and reads without caching", async ({ page }) => {
  await page.goto(`${ORIGIN_URL}/rs-client.html`);
  const result = await page.evaluate(async (token) => {
    const connected = await (window as any).rsProbe.connect("rstest@nextcloud", token, { cache: false });
    if (!connected.ok) {
      return { connected };
    }
    const rs = (window as any).rs;
    const client = rs.scope("/notes/");
    const stamp = `from rs.js ${Date.now()}`;
    const stored = await client.storeFile("text/plain", "sc1.txt", stamp);
    const file = await client.getFile("sc1.txt", false);
    const listing = await client.getListing("", false);
    return {
      connected: { ok: true },
      href: rs.remote.href,
      storageApi: rs.remote.storageApi,
      stamp,
      stored,
      file,
      listing
    };
  }, TOKEN);
  console.log(`[SC1] ${JSON.stringify(result)}`);
  expect(result.connected.ok).toBe(true);
  expect(result.file.data).toBe(result.stamp);
  expect(Object.keys(result.listing)).toContain("sc1.txt");
});

test("SC2 remoteStorage.js with caching: store, sync, read back in a fresh context", async ({ browser }) => {
  const writer = await browser.newContext();
  const page = await writer.newPage();
  await page.goto(`${ORIGIN_URL}/rs-client.html`);
  const stamp = `synced ${Date.now()}`;
  const written = await page.evaluate(async ({ token, stamp }) => {
    const connected = await (window as any).rsProbe.connect("rstest@nextcloud", token);
    if (!connected.ok) {
      return { connected };
    }
    const rs = (window as any).rs;
    const client = rs.scope("/notes/");
    rs.caching.enable("/notes/");
    await client.storeFile("text/plain", "sc2.txt", stamp);
    await new Promise<void>((resolve) => {
      rs.on("sync-done", () => resolve());
      rs.startSync();
    });
    return { connected: { ok: true } };
  }, { token: TOKEN, stamp });
  await writer.close();
  expect(written.connected.ok).toBe(true);

  const reader = await browser.newContext();
  const page2 = await reader.newPage();
  await page2.goto(`${ORIGIN_URL}/rs-client.html`);
  const read = await page2.evaluate(async (token) => {
    const connected = await (window as any).rsProbe.connect("rstest@nextcloud", token);
    if (!connected.ok) {
      return { connected };
    }
    const rs = (window as any).rs;
    rs.caching.enable("/notes/");
    await new Promise<void>((resolve) => {
      rs.on("sync-done", () => resolve());
      rs.startSync();
    });
    const file = await rs.scope("/notes/").getFile("sc2.txt");
    return { connected: { ok: true }, file };
  }, TOKEN);
  await reader.close();
  console.log(`[SC2] ${JSON.stringify({ stamp, read })}`);
  expect(read.connected.ok).toBe(true);
  expect(read.file.data).toBe(stamp);
});
